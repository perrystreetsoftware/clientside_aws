# frozen_string_literal: true

# Allows spec tests to set Time.now, in order to offset future calls to it.
# Optionally uses a Redis instance to share offset between containers.
class Time
  class << self
    # internal, local storage for offset when scruff_redis_instance nil
    attr_accessor :scruff_offset_time
    # set to redis instance to facilitate sharing offset between containers
    attr_accessor :scruff_redis_instance
  end
  Time.scruff_offset_time = 0 # initially there is no offset
  SCRUFF_KEY_OFFSET_TIME = 'scruff_key_offset_time' # redis key for offset
  singleton_class.send(:alias_method, :orig_now, :now) # so we can call Time.now
  # returns offset of patched Time.now
  def self.now
    orig_now - Time.scruff_offset
  end

  # send a Time instance from which to base the offset from or nil for no offset
  def self.now=(time)
    Time.scruff_offset = (time ? orig_now - time : nil)
  end

  # get the current offset in seconds
  def self.scruff_offset
    if Time.scruff_redis_instance.nil?
      Time.scruff_offset_time
    else
      Time.scruff_redis_instance.get(SCRUFF_KEY_OFFSET_TIME).to_i
    end
  end

  # set the current offset in seconds, using scruff_redis_instance if set
  def self.scruff_offset=(secs)
    secs = secs.to_i
    if Time.scruff_redis_instance.nil?
      Time.scruff_offset_time = secs
    else
      Time.scruff_redis_instance.set(SCRUFF_KEY_OFFSET_TIME, secs)
    end
  end
end
