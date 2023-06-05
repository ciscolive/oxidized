module Oxidized
  class HookManager
    # 类方法
    class << self
      def from_config(cfg)
        # 实例化 HookManager
        hook_mgr = new
        cfg.hooks.each do |name, hook_cfg|
          hook_cfg.events.each do |event|
            hook_mgr.register(event.to_sym, name, hook_cfg.type, hook_cfg)
          end
        end
        hook_mgr
      end
    end

    # HookContext is passed to each hook. It can contain anything related to the
    # event in question. At least it contains the event name
    class HookContext < OpenStruct; end

    # RegisteredHook is a container for a Hook instance
    RegisteredHook = Struct.new(:name, :hook)

    # 节点备份任务状态
    Events = %i[
      node_success
      node_fail
      post_store
      nodes_done
    ].freeze

    # 实例对象属性
    attr_reader :registered_hooks

    # 实例化函数
    def initialize
      @registered_hooks = Hash.new { |h, k| h[k] = [] }
    end

    # 节点备份状态钩子函数 -- 备份成功、备份失败、备份完成和数据转储成功
    def register(event, name, hook_type, cfg)
      # 仅支持名单内事件
      raise ArgumentError, "unknown event #{event}, available: #{Events.join(',')}" unless Events.include? event

      # 动态加载钩子模块，如加载异常则抛出异常
      Oxidized.mgr.add_hook(hook_type) || raise("cannot load hook '#{hook_type}', not found")
      begin
        hook = Oxidized.mgr.hook.fetch(hook_type).new
      rescue KeyError
        raise KeyError, "cannot find hook #{hook_type.inspect}"
      end
      # 相关配置
      hook.cfg = cfg

      @registered_hooks[event] << RegisteredHook.new(name, hook)
      Oxidized.logger.debug "Hook #{name.inspect} registered #{hook.class} for event #{event.inspect}"
    end

    # 调用钩子函数
    def handle(event, ctx_params = {})
      ctx = HookContext.new(ctx_params)
      # 关联节点备份状态
      ctx.event = event

      @registered_hooks[event].each do |r_hook|
        r_hook.hook.run_hook(ctx)
      rescue StandardError => e
        Oxidized.logger.error "Hook #{r_hook.name} (#{r_hook.hook}) failed " \
                              "(#{e.inspect}) for event #{event.inspect}"
      end
    end
  end

  # Hook abstract base class
  class Hook
    attr_reader :cfg

    # 设定钩子回调相关配置
    def cfg=(cfg)
      @cfg = cfg
      # 懒加载配置校验函数
      validate_cfg! if respond_to? :validate_cfg!
    end

    # 仅定义不做实现
    def run_hook(_ctx)
      raise NotImplementedError
    end

    # 设置钩子回调日志
    def log(msg, level = :info)
      Oxidized.logger.send(level, "#{self.class.name}: #{msg}")
    end
  end
end
