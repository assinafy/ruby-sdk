# frozen_string_literal: true

module Assinafy
  class NullLogger
    %i[debug info warn error fatal unknown].each do |level|
      define_method(level) { |*, **| nil }
    end
  end
end
