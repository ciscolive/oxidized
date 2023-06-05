class PanOS < Oxidized::Model
  # 动态加载项目定义的字符串提示符
  using Refinements

  # PaloAlto PAN-OS model #

  # 配置注释符
  comment "! "

  # 设置登录成功提示符
  # user@host:~>
  # root@server>
  # (venv) user@host:~>
  prompt(/^[\w.@:()-]+>\s?$/)

  # 所有脚本执行均需要执行的逻辑 -- 自动移除首尾2个行
  cmd :all do |cfg|
    cfg.each_line.to_a[2..-3].join
  end

  # 查看设备信息 -- 屏蔽每天更新变化的信息 --注释回显
  cmd "show system info" do |cfg|
    cfg.gsub!(/^(up)?time: .*$/, "")
    cfg.gsub!(/^app-.*?: .*$/, "")
    cfg.gsub!(/^av-.*?: .*$/, "")
    cfg.gsub!(/^threat-.*?: .*$/, "")
    cfg.gsub!(/^wildfire-.*?: .*$/, "")
    cfg.gsub!(/^wf-private.*?: .*$/, "")
    cfg.gsub!(/^url-filtering.*?: .*$/, "")
    cfg.gsub!(/^global-.*?: .*$/, "")
    comment cfg
  end

  # 查看运行配置
  cmd "show config running"

  # 设定登录后钩子函数脚本配置
  cfg :ssh do
    post_login "set cli pager off"
    pre_logout "quit"
  end
end
