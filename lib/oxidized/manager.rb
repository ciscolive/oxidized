module Oxidized
  require "oxidized/model/model"
  require "oxidized/input/input"
  require "oxidized/output/output"
  require "oxidized/source/source"

  # 自动加载模块
  class Manager
    class << self
      # 动态实例化模块 -- 模块如果实现 setup 方法则自动装配
      def load(dir, file)
        # 懒加载模块
        require File.join(dir, file + ".rb")
        klass = nil
        [Oxidized, Object].each do |mod|
          # casecmp 字符串不区分大小写比较
          klass = mod.constants.find { |const| const.to_s.casecmp(file).zero? }
          klass ||= mod.constants.find { |const| const.to_s.downcase == "oxidized" + file.downcase }
          klass = mod.const_get(klass) if klass
          break if klass
        end
        i = klass&.new
        # 懒加载 setup 方法
        i&.setup if i.respond_to? :setup

        # 用于 merge 数据
        { file => klass }
      rescue LoadError
        false
      end
    end

    # 实例属性 -- 缺省设置为空哈希
    attr_reader :input, :output, :source, :model, :hook

    # 实例化函数
    def initialize
      @input  = {}
      @output = {}
      @source = {}
      @model  = {}
      @hook   = {}
    end

    def add_input(name)
      loader(@input, Config::INPUT_DIR, "input", name)
    end

    def add_output(name)
      loader(@output, Config::OUTPUT_DIR, "output", name)
    end

    def add_source(name)
      loader(@source, Config::SOURCE_DIR, "source", name)
    end

    def add_model(name)
      loader(@model, Config::MODEL_DIR, "model", name)
    end

    def add_hook(name)
      loader(@hook, Config::HOOK_DIR, "hook", name)
    end

    private

    # 优先查找用户定义的模块配置信息
    # if local version of file exists, load it, else load global - return falsy value if nothing loaded
    def loader(hash, global_dir, local_dir, name)
      dir = File.join(Config::ROOT_DIR, local_dir)
      # 优先查找用户本地设定的模块再查询全局模块
      map = Manager.load(dir, name) if File.exist? File.join(dir, name + ".rb")
      map ||= Manager.load(global_dir, name)
      hash.merge!(map) if map
    end
  end
end
