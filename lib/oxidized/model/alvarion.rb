class Alvarion < Oxidized::Model
  using Refinements

  # Used in Alvarion wisp equipment

  # Run this command as an instance of Model so we can access node
  # 输入节点密码
  pre do
    cmd "#{node.auth[:password]}.cfg"
  end

  cfg :tftp do
  end
end
