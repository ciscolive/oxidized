class ALTEONOS < Oxidized::Model
  # 加载项目定义的字符串方法
  using Refinements

  # 设定设备登录成功提示符
  # (user@host) $
  # root#
  # user>
  prompt  /^\(?.+\)?\s?[#>]/

  # 设置注解
  comment '! '

  # 设定脱敏信息
  cmd :secret do |cfg|
    cfg.gsub!(/^([\s\t]*admpw ).*/, '\1 <password removed>')
    cfg.gsub!(/^([\s\t]*pswd ).*/, '\1 <password removed>')
    cfg.gsub!(/^([\s\t]*esecret ).*/, '\1 <password removed>')
    cfg
  end

  ##############################################################################################
  #                                 Added to remove                                            #
  #                                                                                            #
  # /* Configuration dump taken 14:10:20 Fri Jul 28, 2017 (DST)                                #
  # /* Configuration last applied at 16:17:05 Fri Jul 14, 2017                                 #
  # /* Configuration last save at 16:17:43 Fri Jul 14, 2017                                    #
  # /* Version 29.0.3.12, vXXXXXXXX,  Base MAC address XXXXXXXXXXX                             #
  # /* To restore SSL Offloading configuration and management HTTPS access,                    #
  # /* it is recommended to include the private keys in the dump.                              #
  #                                       OR                                                   #
  # /* To restore SSL Offloading configuration and management HTTPS access,it is recommended   #
  # /* to include the private keys in the dump.                                                #
  #                                                                                            #
  ##############################################################################################

  # 打印设备运行配置
  cmd 'cfg/dump' do |cfg|
    cfg.gsub! /^([\s\t\/*]*Configuration).*/, ''
    cfg.gsub! /^([\s\t\/*]*Version).*/, ''
    cfg.gsub! /^([\s\t\/*]*To restore ).*/, ''
    cfg.gsub! /^([\s\t\/*]*it is recommended to include).*/, ''
    cfg.gsub! /^([\s\t\/*]*to include ).*/, ''
    cfg
  end

  # SSH 执行脚本期间自动交互式响应 -> Oxidized::Model#expects
  # Answer for Dispay private keys
  expect /^Display private keys\?\s?\[y\/n\]: $/ do |data, re|
    send "n\r"
    data.sub re, ''
  end

  # Answer for sync to peer on exit
  expect /^Confirm Sync to Peer\s?\[y\/n\]: $/ do |data, re|
    send "n\r"
    data.sub re, ''
  end

  # Answer for  Unsaved configuration
  expect /^(WARNING: There are unsaved configuration changes).*/ do |data, re|
    send "n\r"
    data.sub re, ''
  end

  # 登出前执行 exit
  cfg :ssh do
    pre_logout 'exit'
  end
end
