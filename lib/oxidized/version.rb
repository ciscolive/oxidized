module Oxidized
  VERSION = "0.29.1".freeze
  VERSION_FULL = "0.29.1".freeze

  def self.version_set
    version_full = begin
      %x(git describe --tags).chop
    rescue StandardError
      ""
    end
    version = begin
      %x(git describe --tags --abbrev=0).chop
    rescue StandardError
      ""
    end

    return false unless [version, version_full].none?(&:empty?)

    Oxidized.send(:remove_const, :VERSION)
    Oxidized.send(:remove_const, :VERSION_FULL)
    const_set(:VERSION, version)
    const_set(:VERSION_FULL, version_full)
    file = File.readlines(__FILE__)
    file[1] = "  VERSION = '%s'.freeze\n" % VERSION
    file[2] = "  VERSION_FULL = '%s'.freeze\n" % VERSION_FULL
    File.write(__FILE__, file.join)
  end
end
