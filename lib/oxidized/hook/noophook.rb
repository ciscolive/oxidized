class NoopHook < Oxidized::Hook
  def validate_cfg!
    log "Validate config"
  end

  # 执行回调钩子
  def run_hook(ctx)
    log "Run hook with context: #{ctx}"
  end
end
