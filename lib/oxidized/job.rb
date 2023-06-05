module Oxidized
  class Job < Thread
    # 实例对象属性
    attr_reader :start, :end, :status, :time, :node, :config

    # 节点启用配置备份任务
    # @param [Object] node
    def initialize(node)
      @node  = node
      @start = Time.now.utc + (8 * 60 * 60)
      super do
        Oxidized.logger.debug "lib/oxidized/job.rb: Starting fetching process for #{@node.name} at #{@start}"
        @status, @config = @node.run
        # 设定起止时间
        @end  = Time.now.utc + (8 * 60 * 60)
        @time = @end - @start
        Oxidized.logger.debug "lib/oxidized/job.rb: Config fetched for #{@node.name} at #{@end}"
      end
    end
  end
end
