class VRP < Oxidized::Model
  # 加载项目定义的字符串方法
  using Refinements

  # Huawei VRP

  # 设置登录成功正则表达式
  prompt(/^.*(<[\w.-]+>)$/)

  # 设置配置注释行标识
  comment "# "

  # 数据脱敏
  cmd :secret do |cfg|
    cfg.gsub!(/(pin verify (?:auto|)).*/, '\\1 <PIN hidden>')
    cfg.gsub!(/(%\^%#.*%\^%#)/, "<secret hidden>")
    cfg
  end

  # 抓取全局配置 -- 所有脚本回显均需要裁剪首位行
  cmd :all do |cfg|
    cfg.cut_both
  end

  # 获取版本信息 -- 将回显注释
  cmd "display version" do |cfg|
    cfg = cfg.each_line.reject { |l| l.match(/uptime/) }.join
    comment cfg
  end

  # 获取设备详情 -- 将回显注释
  cmd "display device" do |cfg|
    comment cfg
  end

  # 获取运行配置 -- 直接输出无需修饰
  cmd "display current-configuration all"

  # telnet 登录期间设置交互变量
  cfg :telnet do
    username(/^Username:$/)
    password(/^Password:$/)
  end

  # 登录后自动执行的钩子函数
  cfg :telnet, :ssh do
    post_login "screen-length 0 temporary"
    pre_logout "save force"
    pre_logout "quit"
  end
end
