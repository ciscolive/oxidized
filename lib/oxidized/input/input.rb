module Oxidized
  class PromptUndetect < OxidizedError; end

  class Input
    include Oxidized::Config::Vars

    # 通用的异常模型
    RescueFail = {
      debug: [
        Errno::ECONNREFUSED
      ],
      warn:  [
        IOError,
        PromptUndetect,
        Timeout::Error,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        Errno::EPIPE,
        Errno::ETIMEDOUT
      ]
    }.freeze
  end
end
