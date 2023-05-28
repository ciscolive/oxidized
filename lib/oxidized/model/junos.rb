class JunOS < Oxidized::Model
  # 加载项目定义的字符串方法
  using Refinements

  # 脚本注释行符
  comment '# '

  # 判定是否 telnet 登录
  def telnet
    @input.class.to_s.match(/Telnet/)
  end

  # 执行的脚本均需要处理的逻辑
  cmd :all do |cfg|
    cfg = cfg.cut_both if screenscrape
    cfg.gsub!(/  scale-subscriber (\s+)(\d+)/, '  scale-subscriber                <count>')
    cfg.lines.map { |line| line.rstrip }.join("\n") + "\n"
  end

  # 数据脱敏脚本
  cmd :secret do |cfg|
    cfg.gsub!(/community (\S+) {/, 'community <hidden> {')
    cfg.gsub!(/ "\$\d\$\S+; ## SECRET-DATA/, ' <secret removed>;')
    cfg
  end

  # 查看设备版本 -- 动态设置设备版本同时注释脚本
  cmd 'show version' do |cfg|
    @model = Regexp.last_match(1) if cfg =~ /^Model: (\S+)/
    comment cfg
  end

  # 动态执行脚本 -- 不同设备脚本不一样
  # 根据设备类型执行个性化脚本并注释
  post do
    out = ''
    case @model
    when 'mx960'
      out << cmd('show chassis fabric reachability') { |cfg| comment cfg }
    when /^(ex22|ex33|ex4|ex8|qfx)/
      out << cmd('show virtual-chassis') { |cfg| comment cfg }
    end
    out
  end

  # 查看设备硬件信息 -- 注释回显
  cmd('show chassis hardware') { |cfg| comment cfg }

  # 查看设备授权信息 -- 注释回显
  cmd('show system license') do |cfg|
    cfg.gsub!(/  fib-scale\s+(\d+)/, '  fib-scale                       <count>')
    cfg.gsub!(/  rib-scale\s+(\d+)/, '  rib-scale                       <count>')
    comment cfg
  end

  # 查看系统授权证书 -- 注释回显
  cmd('show system license keys') { |cfg| comment cfg }

  # 查看设备运行配置 -- 无需注释
  cmd 'show configuration | display omit'

  # 设置 telnet 登录相关参数
  cfg :telnet do
    username(/^login:/)
    password(/^Password:/)
  end

  # 设定 ssh 脚本执行使用 channel
  # 直接在 EXEC CHANNEL 执行脚本
  cfg :ssh do
    exec true # don't run shell, run each command in exec channel
  end

  # 设备登录成功钩子函数脚本
  cfg :telnet, :ssh do
    post_login 'set cli screen-length 0'
    post_login 'set cli screen-width 0'
    pre_logout 'exit'
  end
end
