class NXOS < Oxidized::Model
  # 加载项目项目定义的字符串方法
  using Refinements

  # 设备登录成功提示符
  # user@host:~$
  # root@server:#
  # (venv) user@host:$
  prompt /^(\r?[\w.@_()-]+[#]\s?)$/

  # 配置注释符
  comment '! '

  # 脚本显示修正
  def filter(cfg)
    cfg.gsub! /\r\n?/, "\n"
    # cfg.gsub! prompt, ''
  end

  # 配置脱敏规则
  cmd :secret do |cfg|
    cfg.gsub! /^(snmp-server community).*/, '\\1 <configuration removed>'
    cfg.gsub! /^(snmp-server user (\S+) (\S+) auth (\S+)) (\S+) (priv) (\S+)/, '\\1 <configuration removed> '
    cfg.gsub! /(password \d+) (\S+)/, '\\1 <secret hidden>'
    cfg.gsub! /^(radius-server key).*/, '\\1 <secret hidden>'
    cfg.gsub! /^(tacacs-server host .+ key(?: \d+)?) \S+/, '\\1 <secret hidden>'
    cfg
  end

  # 查看设备版本信息 -- 注释回显
  cmd 'show version' do |cfg|
    cfg = filter cfg
    cfg = cfg.each_line.take_while { |line| not line.match(/uptime/i) }
    comment cfg.join
  end

  # 查看设备硬件信息 -- 注释回显
  cmd 'show inventory' do |cfg|
    cfg = filter cfg
    comment cfg
  end

  # 查看设备运行配置 -- 替换经常变化的字串
  cmd 'show running-config' do |cfg|
    cfg = filter cfg
    cfg.gsub! /^(show run.*)$/, '! \1'
    cfg.gsub! /^!Time:[^\n]*\n/, ''
    cfg.gsub! /^[\w.@_()-]+[#].*$/, ''
    cfg
  end

  # 设定登录后钩子函数脚本
  cfg :ssh, :telnet do
    post_login 'terminal length 0'
    pre_logout 'copy run start'
    pre_logout 'exit'
  end

  # 设置 telnet 交互提示符
  cfg :telnet do
    username /^login:/
    password /^Password:/
  end
end
