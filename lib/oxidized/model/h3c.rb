class H3C < Oxidized::Model
  # 加载项目定义的字符串方法
  using Refinements

  # H3C
  # 设定登录成功提示符
  prompt /^.*(<[\w.-]+>)$/
  # 设定配置注释符
  comment '# '

  # 设置脚本脱敏信息
  # 执行完脚本的回显作为输入传递给到代码块进一步处理
  cmd :secret do |cfg|
    cfg.gsub! /(pin verify (?:auto|)).*/, '\\1 <PIN hidden>'
    cfg.gsub! /(%\^%#.*%\^%#)/, '<secret hidden>'
    cfg
  end

  # 设置配置裁剪逻辑 -- 将脚本输出首尾行删除
  cmd :all do |cfg|
    cfg.cut_both
  end

  # 获取设备版本信息 -- 将设备版本信息注释，同时过滤掉 Uptime 行信息
  cmd 'display version' do |cfg|
    cfg = cfg.each_line.reject { |l| l.match(/uptime/i) }.join
    comment cfg
  end

  # 获取设备详情 -- 将设备详情的配置注释
  cmd 'display device' do |cfg|
    comment cfg
  end

  # 获取运行配置
  cmd 'display current-configuration'

  # 设置 telnet 登录相关凭证
  cfg :telnet do
    username /^Username:$/
    password /^Password:$/
  end

  # 设置 SSH 和 TELNET 登录成功钩子函数脚本
  cfg :telnet, :ssh do
    post_login 'screen-length disable'
    pre_logout 'save force'
    pre_logout 'quit'
  end
end
