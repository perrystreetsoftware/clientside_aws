
# Uses Time.now, so today can be set via spec tests if patched Time being used.
class Date
  def self.today
    Time.now.to_date
  end
end
