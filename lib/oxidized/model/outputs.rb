module Oxidized
  class Model
    using Refinements

    class Outputs
      def to_cfg
        type_to_str(nil)
      end

      # 配置转字符串
      def type_to_str(want_type)
        type(want_type).map { |out| out }.join
      end

      # 追加脚本到数组尾部
      def <<(output)
        @outputs << output
      end

      # 追加脚本到数组头部
      def unshift(output)
        @outputs.unshift output
      end

      # 全部脚本
      def all
        @outputs
      end

      # 设置脚本输出类型
      def type(type)
        @outputs.select { |out| out.type == type }
      end

      # 脚本输出类型
      def types
        @outputs.map { |out| out.type }.uniq.compact
      end

      private

      # 实例初始化函数
      def initialize
        @outputs = []
      end
    end
  end
end
