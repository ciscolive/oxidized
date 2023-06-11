module Oxidized
  require "oxidized/job"
  require "oxidized/jobs"

  # 工作队列
  class Worker
    # 实例化函数 -- 线程异常则跳出
    def initialize(nodes)
      @jobs_done  = 0
      @nodes      = nodes
      @jobs       = Jobs.new(Oxidized.config.threads, Oxidized.config.use_max_threads, Oxidized.config.interval, @nodes)
      @nodes.jobs = @jobs
      # 线程异常是否跳出
      Thread.abort_on_exception = true
    end

    # 启动备份任务
    def work
      ended = []
      # 过滤已完成备份任务的节点清单
      @jobs.delete_if { |job| ended << job unless job.alive? }
      ended.each { |job| process(job) }
      @jobs.work

      while @jobs.size < @jobs.want
        Oxidized.logger.debug "lib/oxidized/worker.rb: Jobs running: #{@jobs.size} of #{@jobs.want} - ended: #{@jobs_done} of #{@nodes.size}"
        # ask for next node in queue non destructive way
        # 先进先出 FIFO
        next_node = @nodes.first
        unless next_node.last.nil?
          # Set unobtainable value for 'last' if interval checking is disabled
          last = Oxidized.config.interval.zero? ? Time.now.utc + (8 * 60 * 60) + 10 : next_node.last.end
          break if last + Oxidized.config.interval > Time.now.utc + (8 * 60 * 60)
        end

        # 登录节点并提取配置快照
        # shift nodes and get the next node
        node = @nodes.get
        node.running? ? next : node.running = true

        @jobs.push Job.new(node)
        Oxidized.logger.debug "lib/oxidized/worker.rb: Added #{node.group}/#{node.name} to the job queue"
      end

      run_done_hook if cycle_finished?
      Oxidized.logger.debug("lib/oxidized/worker.rb: #{@jobs.size} jobs running in parallel") unless @jobs.empty?
    end

    # 根据任务状态运行对应的钩子函数
    def process(job)
      node      = job.node
      node.last = job
      node.stats.add(job)
      @jobs.duration(job.time)
      node.running = false
      if job.status == :success
        process_success(node, job)
      else
        process_failure(node, job)
      end
    rescue NodeNotFound
      Oxidized.logger.warn "#{node.group}/#{node.name} not found, removed while collecting?"
    end

    private

    # 节点备份成功回调钩子
    def process_success(node, job)
      @jobs_done += 1 # needed for :nodes_done hook
      Oxidized.hooks.handle(:node_success, node: node, job: job)
      # 设定节点备份成功消息
      msg = "update #{node.group}/#{node.name}"
      msg << " from #{node.from}" if node.from
      msg << " with message '#{node.msg}'" if node.msg

      # 实例化节点配置备份模式
      output = node.output.new
      if output.store(node.name, job.config, msg: msg, email: node.email, user: node.user, group: node.group)
        # 更新节点配置时间戳
        node.modified
        Oxidized.logger.info "Configuration updated for #{node.group}/#{node.name}"
        Oxidized.hooks.handle(:post_store, node: node, job: job, commitref: output.commitref)
      end
      node.reset
    end

    # 节点备份异常回调钩子
    def process_failure(node, job)
      msg = "#{node.group}/#{node.name} status #{job.status}"
      if node.retry < Oxidized.config.retries
        node.retry += 1
        # 设定重试消息
        msg << ", retry attempt #{node.retry}"
        @nodes.next(node.name)
      else
        # Only increment the @jobs_done when we give up retries for a node (or success).
        # As it would otherwise cause @jobs_done to be incremented with generic retries.
        # This would cause :nodes_done hook to desync from running at the end of the nodelist and
        # be fired when the @jobs_done > @nodes.count (could be mid-cycle on the next cycle).
        @jobs_done += 1
        node.retry = 0
        # 设定重试超次数消息
        msg << ", retries exhausted, giving up"
        Oxidized.hooks.handle(:node_fail, node: node, job: job)
      end
      Oxidized.logger.warn(msg)
    end

    # 判定备份任务是否全部执行
    def cycle_finished?
      if @jobs_done > @nodes.count
        true
      else
        @jobs_done.positive? && (@jobs_done % @nodes.count).zero?
      end
    end

    # 任务运行完成回调钩子
    def run_done_hook
      Oxidized.logger.debug "lib/oxidized/worker.rb: Running :nodes_done hook"
      Oxidized.hooks.handle(:nodes_done)
    rescue StandardError => e
      # swallow the hook errors and continue as normal
      Oxidized.logger.error "lib/oxidized/worker.rb: #{e.message}"
    ensure
      @jobs_done = 0
    end
  end
end
