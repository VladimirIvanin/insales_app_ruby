module Insales
  class ShopNotAllowed < Error
    def initialize
      super("Shop is not allowed")
    end
  end
end
