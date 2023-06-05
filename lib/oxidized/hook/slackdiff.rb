require "slack"

# defaults to posting a diff, if messageformat is supplied them a message will be posted too
# diff defaults to true

class SlackDiff < Oxidized::Hook
  # 校验 SlackDiff 配置
  def validate_cfg!
    raise KeyError, "hook.token is required" unless cfg.has_key?("token")
    raise KeyError, "hook.channel is required" unless cfg.has_key?("channel")
  end

  # 执行回调钩子
  def run_hook(ctx)
    return unless ctx.node
    return unless ctx.event.to_s == "post_store"

    # 打印连接日志
    log "Connecting to slack"

    # 设定 slack 相关配置
    Slack::Web::Client.configure do |config|
      config.token = cfg.token
      config.proxy = cfg.proxy if cfg.has_key?("proxy")
    end
    client = Slack::Web::Client.new
    client.auth_test
    log "Connected"

    if cfg.has_key?("diff") ? cfg.diff : true
      git_output = ctx.node.output.new
      diff       = git_output.get_diff ctx.node, ctx.node.group, ctx.commitref, nil
      unless diff == "no diffs"
        title = "#{ctx.node.name} #{ctx.node.group} #{ctx.node.model.class.name.to_s.downcase}"
        # 打印 diff 日志
        log "Posting diff as snippet to #{cfg.channel}"

        # 上传相关差异文件
        client.files_upload(channels: cfg.channel, as_user: true,
                            content:  diff[:patch].lines.to_a[4..-1].join,
                            filetype: "diff",
                            title:    title,
                            filename: "change")
      end
    end
    # message custom formatted - optional
    if cfg.message?
      # 打印日志
      log cfg.message
      msg = cfg.message % { node: ctx.node.name.to_s, group: ctx.node.group.to_s, commitref: ctx.commitref, model: ctx.node.model.class.name.to_s.downcase }
      log msg
      log "Posting message to #{cfg.channel}"
      client.chat_postMessage(channel: cfg.channel, text: msg, as_user: true)
    end
    log "Finished"
  end
end
