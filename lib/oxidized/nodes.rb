module Oxidized
  require "ipaddr"
  require "oxidized/node"

  class Oxidized::NotSupported < OxidizedError; end

  class Oxidized::NodeNotFound < OxidizedError; end

  # nodes 默认继承数组对象
  class Nodes < Array
    # 实例属性
    attr_accessor :source, :jobs
    alias put unshift

    def load(node_want = nil)
      with_lock do
        new = []
        @source = Oxidized.config.source.default
        Oxidized.mgr.add_source(@source) || raise(MethodNotFound, "cannot load node source '#{@source}', not found")
        Oxidized.logger.info "lib/oxidized/nodes.rb: Loading nodes"

        # 加载数据源并展开为 nodes 对象
        nodes = Oxidized.mgr.source[@source].new.load(node_want)
        nodes.each do |node|
          # we want to load specific node(s), not all of them
          # 一般用于页面直接发起配置备份任务
          next unless node_want?(node_want, node)

          begin
            node_obj = Node.new(node)
            new.push(node_obj)
          rescue ModelNotFound => err
            Oxidized.logger.error "node %s raised %s with message '%s'" % [node, err.class, err.message]
          rescue Resolv::ResolvError => err
            Oxidized.logger.error "node %s is not resolvable, raised %s with message '%s'" % [node, err.class, err.message]
          end
        end
        size.zero? ? replace(new) : update_nodes(new)
        Oxidized.logger.info "lib/oxidized/nodes.rb: Loaded #{size} nodes"
      end
    end

    # 加载特定的节点任务 -- 菜单按钮直接发起配置备份
    def node_want?(node_want, node)
      return true unless node_want

      node_want_ip = begin
        IPAddr.new(node_want)
      rescue StandardError
        false
      end
      name_is_ip = begin
        IPAddr.new(node[:name])
      rescue StandardError
        false
      end
      # rubocop:todo Lint/DuplicateBranch
      if name_is_ip && (node_want_ip == node[:name])
        true
      elsif node[:ip] && (node_want_ip == node[:ip])
        true
      elsif node_want.match node[:name]
        true unless name_is_ip
      end
      # rubocop:enable Lint/DuplicateBranch
    end

    # 列出所有节点清单 -- 线程锁
    def list
      with_lock do
        map { |e| e.serialize }
      end
    end

    # 查询特定节点信息 -- 线程锁
    def show(node)
      with_lock do
        i = find_node_index(node)
        self[i].serialize
      end
    end

    # 根据设备名称和属组查询输出配置 -- 查询节点配置信息(节点名称、属组)
    def fetch(node_name, group)
      yield_node_output(node_name) do |node, output|
        output.fetch(node, group)
      end
    end

    # 下一个节点继续运行备份任务
    # @param node [String] name of the node moved into the head of array
    def next(node, opt = {})
      # 确保节点非运行状态
      return unless waiting.find_node_index(node)

      with_lock do
        n = del node
        n.user = opt["user"]
        n.email = opt["email"]
        n.msg = opt["msg"]
        n.from = opt["from"]
        # set last job to nil so that the node is picked for immediate update
        n.last = nil
        put n.inspect
        jobs.want += 1 if Oxidized.config.next_adds_job?
      end
    end

    alias top next

    # 先进先出 -- 提取队列头部数据
    # @return [String] node from the head of the array
    def get
      with_lock do
        (self << shift).last
      end
    end

    # @param node node whose index number in Nodes to find
    # @return [Fixnum] index number of node in Nodes
    def find_node_index(node)
      find_index(node) || raise(Oxidized::NodeNotFound, "unable to find '#{node}'")
    end

    # 查询节点配置版本
    def version(node_name, group)
      yield_node_output(node_name) do |node, output|
        output.version node, group
      end
    end

    # 查询节点配置版本
    def get_version(node_name, group, oid)
      yield_node_output(node_name) do |node, output|
        output.get_version(node, group, oid)
      end
    end

    # 查询版本差量
    def get_diff(node_name, group, oid1, oid2)
      yield_node_output(node_name) do |node, output|
        output.get_diff(node, group, oid1, oid2)
      end
    end

    private

    # 实例化函数
    def initialize(opts = {})
      super()
      @mutex = Mutex.new # we compete for the nodes with webapi thread
      if (nodes = opts.delete(:nodes))
        replace(nodes)
      else
        node = opts.delete(:node)
        load(node)
      end
    end

    # 执行给定的代码块时对一个互斥锁进行加锁和解锁操作
    # & 符号用于将代码块转换为 Proc 对象
    # 确保在多线程环境中，同一时间只有一个线程可以执行代码块内的操作，
    # 避免并发访问引起的竞态条件和数据不一致性问题
    def with_lock(&block)
      @mutex.synchronize(&block)
    end

    # 节点数组对象中查询特定节点索引
    # @param node node which looking for index
    # @return [Fixnum] node
    def find_index(node)
      index { |e| [e.name, e.ip].include? node }
    end

    # @param node node which is removed from nodes list
    # @return [Node] deleted node
    def del(node)
      delete_at(find_node_index(node))
    end

    # 已运行备份的节点
    # @return [Nodes] list of nodes running now
    def running
      Nodes.new nodes: select { |node| node.running? }
    end

    # 待运行备份任务的节点 -- 飞运行状态
    # @return [Nodes] list of nodes waiting (not running)
    def waiting
      Nodes.new nodes: select { |node| !node.running? }
    end

    # walks list of new nodes, if old node contains same name, adds last and
    # stats information from old to new.
    #
    # @todo can we trust name to be unique identifier, what about when groups are used?
    # @param [Array] nodes Array of nodes used to replace+update old
    def update_nodes(nodes)
      # 复制原有数组，并替换为最新的节点信息
      old = dup
      replace(nodes)
      # 遍历每个节点一次运行备份任务
      each do |node|
        if (i = old.find_node_index(node.name))
          node.stats = old[i].stats
          node.last = old[i].last
        end
      rescue Oxidized::NodeNotFound
        Oxidized.logger.error "#{node.name} NodeNotFound"
      end
      sort_by! { |x| x.last.nil? ? Time.new(2023) : x.last.end }
    end

    # 将运行配置转储 -- 线程锁
    def yield_node_output(node_name)
      with_lock do
        node = find { |n| n.name == node_name }
        output = node&.output&.new
        raise Oxidized::NotSupported unless output.respond_to? :fetch

        yield node, output
      end
    end
  end
end
