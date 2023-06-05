module Oxidized
  class Jobs < Array
    # 定义备份常规计时器
    AVERAGE_DURATION = 5 # initially presume nodes take 5s to complete
    MAX_INTER_JOB_GAP = 300 # add job if more than X from last job started

    # 实例对象属性
    attr_accessor :interval, :max, :want

    # 初始化函数
    def initialize(max, use_max_threads, interval, nodes)
      @max = max
      @use_max_threads = use_max_threads
      # Set interval to 1 if interval is 0 (=disabled) so we don't break
      # the 'ceil' function
      @interval = interval.zero? ? 1 : interval
      @nodes = nodes
      @last = Time.now.utc + (8 * 60 * 60)
      @durations = Array.new @nodes.size, AVERAGE_DURATION
      duration AVERAGE_DURATION
      super()
    end

    # 增加时间属性
    def push(arg)
      @last = Time.now.utc + (8 * 60 * 60)
      super
    end

    # 设定节点运行平均时长
    def duration(last)
      # 编排 @durations：如果队列大于@nodes则删减，小于@nodes则补充
      if @durations.size > @nodes.size
        @durations.slice! @nodes.size...@durations.size
      elsif @durations.size < @nodes.size
        @durations.fill AVERAGE_DURATION, @durations.size...@nodes.size
      end
      # 尾部追加最新节点 -- 先进先出
      @durations.push(last).shift
      @duration = @durations.inject(:+).to_f / @nodes.size # rolling average
      new_count
    end

    # 自动设置线程数：(节点数*平均超时时间)/单节点运行周期
    def new_count
      @want = if @use_max_threads
        @max
      else
        ((@nodes.size * @duration) / @interval).ceil
      end
      @want = 1 if @want < 1
      @want = @nodes.size if @want > @nodes.size
      @want = @max if @want > @max
    end

    def work
      # if   a) we want less or same amount of threads as we now running
      # and  b) we want less threads running than the total amount of nodes
      # and  c) there is more than MAX_INTER_JOB_GAP since last one was started
      # then we want one more thread (rationale is to fix hanging thread causing HOLB)
      return unless @want <= size && @want < @nodes.size

      @want += 1 if (Time.now.utc + (8 * 60 * 60) - @last) > MAX_INTER_JOB_GAP
    end
  end
end
