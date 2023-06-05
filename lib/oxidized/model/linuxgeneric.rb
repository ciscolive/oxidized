class LinuxGeneric < Oxidized::Model
  # 加载项目字符串方法
  using Refinements

  # 设备登录成功提示符
  prompt(/^(\w.*|\W.*)(:|#) /)

  # 配置注释符号
  comment "# "

  # add a comment in the final conf
  def add_comment(comment)
    "\n###### #{comment} ######\n"
  end

  # 所有脚本需要预处理的逻辑
  cmd :all do |cfg|
    cfg.gsub!(/^(default (\S+).* (expires) ).*/, '\\1 <redacted>')
    cfg.cut_both
  end

  # show the persistent configuration
  pre do
    cfg = add_comment "THE HOSTNAME"
    cfg += cmd "cat /etc/hostname"

    cfg += add_comment "THE HOSTS"
    cfg += cmd "cat /etc/hosts"

    cfg += add_comment "THE INTERFACES"
    cfg += cmd "ip link"

    cfg += add_comment "RESOLV.CONF"
    cfg += cmd "cat /etc/resolv.conf"

    cfg += add_comment "IP Routes"
    cfg += cmd "ip route"

    cfg += add_comment "IPv6 Routes"
    cfg += cmd "ip -6 route"

    cfg += add_comment "MOTD"
    cfg += cmd "cat /etc/motd"

    cfg += add_comment "PASSWD"
    cfg += cmd "cat /etc/passwd"

    cfg += add_comment "GROUP"
    cfg += cmd "cat /etc/group"

    cfg += add_comment "nsswitch.conf"
    cfg += cmd "cat /etc/nsswitch.conf"

    cfg += add_comment "VERSION"
    cfg += cmd "cat /etc/issue"

    cfg
  end

  # telnet 登录账户相关信息
  cfg :telnet do
    username(/^Username:/)
    password(/^Password:/)
  end

  # 设备登录钩子函数相关参数
  cfg :telnet, :ssh do
    # 登录成功后自动切换 su
    post_login do
      if vars(:enable) == true
        cmd "sudo su -", /^\[sudo\].*?password/
        cmd @node.auth[:password]
      elsif vars(:enable)
        cmd "su -", /^Password:/
        cmd vars(:enable)
      end
    end

    # 退出前钩子
    pre_logout do
      cmd "exit" if vars(:enable)
    end
    pre_logout "exit"
  end
end
