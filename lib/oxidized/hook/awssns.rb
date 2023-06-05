require "aws-sdk"

class AwsSns < Oxidized::Hook
  # 自动校验 aws_sns 回调配置
  def validate_cfg!
    raise KeyError, "hook.region is required" unless cfg.has_key?("region")
    raise KeyError, "hook.topic_arn is required" unless cfg.has_key?("topic_arn")
  end

  # 运行回调函数
  def run_hook(ctx)
    sns = Aws::SNS::Resource.new(region: cfg.region)
    topic = sns.topic(cfg.topic_arn)
    message = {
      event: ctx.event.to_s
    }
    if ctx.node
      message.merge!(
        group: ctx.node.group.to_s,
        model: ctx.node.model.class.name.to_s.downcase,
        node: ctx.node.name.to_s
      )
    end
    topic.publish(message: message.to_json)
  end
end
