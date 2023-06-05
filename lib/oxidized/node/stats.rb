module Oxidized
  class Node
    class Stats
      # 对象属性
      attr_reader :mtimes

      MAX_STAT = 10

      # @param [Job] job job whose information add to stats
      # @return [void]
      def add(job)
        stat = {
          start: job.start,
          end:   job.end,
          time:  job.time
        }

        # 先进先出 -- 排队逻辑
        @stats[job.status] ||= []
        @stats[job.status].shift if @stats[job.status].size > @history_size
        @stats[job.status].push stat
        @stats[:counter][job.status] += 1
      end

      # 查询节点状态
      # @param [Symbol] status stats for specific status
      # @return [Hash,Array] Hash of stats for every status or Array of stats for specific status
      def get(status = nil)
        status ? @stats[status] : @stats
      end

      # 查询节点状态计数器 -- 支持分类查询
      def get_counter(counter = nil)
        counter ? @stats[:counter][counter] : @stats[:counter]
      end

      # 查询备份成功的清单
      def successes
        @stats[:counter][:success]
      end

      # 查询备份异常的清单
      def failures
        @stats[:counter].reduce(0) { |m, h| h[0] == :success ? m : m + h[1] }
      end

      # 节点任务修改时间
      def mtime
        mtimes.last
      end

      # 更新时间 -- 刷新机制
      def update_mtime
        @mtimes.push(Time.now.utc + (8 * 60 * 60))
        @mtimes.shift
      end

      private

      # 实例化函数
      def initialize
        @history_size = Oxidized.config.stats.history_size? || MAX_STAT
        @mtimes = Array.new(@history_size, Time.now.utc + (8 * 60 * 60))
        @stats = {}
        @stats[:counter] = Hash.new 0
      end
    end
  end
end
