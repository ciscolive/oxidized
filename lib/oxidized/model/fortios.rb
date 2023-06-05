class FortiOS < Oxidized::Model
  # 加载项目字符串方法
  using Refinements

  # 脚本注释符号
  comment "# "

  # 登录设备成功提示符
  prompt(/^([-\w.~]+(\s[(\w\-.)]+)?~?\s?[#>$]\s?)$/)

  # 交互执行脚本 -- 自动加载更多配置
  expect(/^--More--\s$/) do |data, re|
    send " "
    data.sub re, ""
  end

  # 所有输出均需要处理的逻辑
  cmd :all do |cfg, cmdstring|
    new_cfg = comment "COMMAND: #{cmdstring}\n"
    new_cfg << cfg.each_line.to_a[1..-2].map { |line| line.gsub(/(conf_file_ver=)(.*)/, '\1<stripped>\3') }.join
  end

  # 数据脱敏逻辑
  cmd :secret do |cfg|
    # ENC indicates an encrypted password, and secret indicates a secret string
    cfg.gsub!(/(set .+ ENC) .+/, '\\1 <configuration removed>')
    cfg.gsub!(/(set .*secret) .+/, '\\1 <configuration removed>')
    # A number of other statements also contains sensitive strings
    cfg.gsub!(/(set (?:passwd|password|key|group-password|auth-password-l1|auth-password-l2|rsso|history0|history1)) .+/, '\\1 <configuration removed>')
    cfg.gsub!(/(set md5-key [0-9]+) .+/, '\\1 <configuration removed>')
    cfg.gsub!(/(set private-key ).*?-+END (ENCRYPTED|RSA|OPENSSH) PRIVATE KEY-+\n?"$/m, '\\1<configuration removed>')
    cfg.gsub!(/(set ca )"-+BEGIN.*?-+END CERTIFICATE-+"$/m, '\\1<configuration removed>')
    cfg.gsub!(/(set csr ).*?-+END CERTIFICATE REQUEST-+"$/m, '\\1<configuration removed>')
    cfg
  end

  # 查询设备运行配置
  cmd "get system status" do |cfg|
    @vdom_enabled = cfg.match(/Virtual domain configuration: (enable|multiple)/)
    cfg.gsub!(/(System time:).*/, '\\1 <stripped>')
    cfg.gsub!(/(Cluster (?:uptime|state change time):).*/, '\\1 <stripped>')
    cfg.gsub!(/(Current Time\s+:\s+)(.*)/, '\1<stripped>')
    cfg.gsub!(/(Uptime:\s+)(.*)/, '\1<stripped>\3')
    cfg.gsub!(/(Last reboot:\s+)(.*)/, '\1<stripped>\3')
    cfg.gsub!(/(Disk Usage\s+:\s+)(.*)/, '\1<stripped>')
    cfg.gsub!(/(^\S+ (?:disk|DB):\s+)(.*)/, '\1<stripped>\3')
    cfg.gsub!(/(VM Registration:\s+)(.*)/, '\1<stripped>\3')
    cfg.gsub!(/(Virus-DB|Extended DB|IPS-DB|IPS-ETDB|APP-DB|INDUSTRIAL-DB|Botnet DB|IPS Malicious URL Database|AV AI\/ML Model|IoT-Detect).*/, '\\1 <db version stripped>')
    comment cfg
  end

  post do
    cfg = []
    # 如果启用 vdom 切入全局配置
    cfg << cmd("config global") if @vdom_enabled

    # 查看设备 HA 状态
    cfg << cmd("get system ha status") do |cfg_ha|
      cfg_ha = cfg_ha.each_line.select { |line| line.match(/^(HA Health Status|Mode|Model|Master|Slave|Primary|Secondary|# COMMAND)(\s+)?:/) }.join
      comment cfg_ha
    end

    # 查看设备硬件属性
    cfg << cmd("get hardware status") do |cfg_hw|
      comment cfg_hw
    end

    # default behaviour: include autoupdate output (backwards compatibility)
    # do not include if variable "show_autoupdate" is set to false
    if defined?(vars(:fortios_autoupdate)).nil? || vars(:fortios_autoupdate)
      cfg << cmd("diagnose autoupdate version") do |cfg_auto|
        cfg_auto.gsub!(/(FDS Address\n---------\n).*/, '\\1IP Address removed')
        comment cfg_auto.each_line.reject { |line| line.match(/Last Update|Result/) }.join
      end
    end

    cfg << cmd("end") if @vdom_enabled

    ["show full-configuration | grep .", "show full-configuration", "show"].each do |fullcmd|
      fullcfg = cmd(fullcmd)
      next if /(Parsing error at|command parse error)/.match?(fullcfg.lines[1..3].join) # Don't show for unsupported devices (e.g. FortiAnalyzer, FortiManager, FortiMail)

      cfg << fullcfg
      break
    end

    cfg.join
  end

  # 设置 telnet 账户认证参数
  cfg :telnet do
    username(/^[lL]ogin:/)
    password(/^Password:/)
  end

  # 设备登录钩子函数配置
  cfg :telnet, :ssh do
    pre_logout "exit\n"
  end
end
