class StoneOS < Oxidized::Model
  # 加载项目定义的字符串方法
  using Refinements

  # Hillstone Networks StoneOS software

  # 设定设备登录成功提示符
  # user@host:~>
  # root@server#
  # (venv) user@host:~
  prompt /^\r?[\w.()-]+~?[#>](\s)?$/

  # 配置注释符
  comment '# '

  # 交互式执行多页输出
  expect /^\s.*--More--.*$/ do |data, re|
    send ' '
    data.sub re, ''
  end

  # 针对每个命令自动执行裁剪 -- 去除首位行
  cmd :all do |cfg|
    cfg.gsub! /+.*+/, '' # Linebreak handling
    cfg.cut_both
  end

  # 查看设备运行配置 -- 替换经常变化的字串
  cmd 'show configuration running' do |cfg|
    cfg.gsub! /^Building configuration.*$/, ''
  end

  # 查看设备版本消息 -- 注释回显
  cmd 'show version' do |cfg|
    cfg.gsub! /^Uptime is .*$/, ''
    comment cfg
  end

  # 设定 telnet 交互式变量
  cfg :telnet do
    username(/^login:/)
    password(/^Password:/)
  end

  # 设定登陆成功钩子函数脚本
  cfg :telnet, :ssh do
    post_login 'terminal length 256'
    post_login 'terminal width 512'
    pre_logout 'exit'
  end
end
