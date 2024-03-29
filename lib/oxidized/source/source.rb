module Oxidized
  class Source
    class NoConfig < OxidizedError; end

    # 实例化函数
    def initialize
      @model_map = (Oxidized.config.model_map || {})
      @group_map = (Oxidized.config.group_map || {})
    end

    # 加载配置文件的模型和属组信息
    def map_model(model)
      @model_map.has_key?(model) ? @model_map[model] : model
    end

    def map_group(group)
      @group_map.has_key?(group) ? @group_map[group] : group
    end

    # 变量插值
    def node_var_interpolate(var)
      case var
      when "nil" then nil
      when "false" then false
      when "true" then true
      else var
      end
    end
  end
end
