module Worker
  @queue = :default

  def self.thread_id
    "#{Process.pid}_#{Thread.current.object_id}"
  end
  
  def self.schedule(klass, method_name, *args)
    Resque.enqueue(Worker, klass.to_s, method_name, *args)
  end
  
  def self.perform(*args)
    args_copy = [] + args
    klass_string = args_copy.shift
    klass = Object.const_get(klass_string)
    method_name = args_copy.shift
    klass.send(method_name, *args_copy)
  rescue Resque::TermException
    Resque.enqueue(self, *args)
  end
  
  def self.on_failure_retry(e, *args)
    # TODO...
  end
  
  def self.scheduled?(klass, method_name, *args)
    idx = Resque.size('default')
    idx.times do |i|
      schedule = Resque.peek('default', i)
      if schedule['class'] == 'Worker' && schedule['args'][0] == klass.to_s && schedule['args'][1] == method_name.to_s
        if args.to_json == schedule['args'][2..-1].to_json
          return true
        end
      end
    end
    return false
  end
  
  def self.stop_stuck_workers
    timeout = 8.hours.to_i
    Resque.workers.each {|w| w.unregister_worker if w.processing['run_at'] && Time.now - w.processing['run_at'].to_time > timeout}    
  end
  
  def self.process_queues
    schedules = []
    Resque.queues.each do |key|
      while Resque.size(key) > 0
        schedules << Resque.pop(key)
      end
    end
    schedules.each do |schedule|
      raise "unknown job: #{schedule.to_json}" if schedule['class'] != 'Worker'
      Worker.perform(*(schedule['args']))
    end
  end
  
  def self.queues_empty?
    found = false
    Resque.queues.each do |key|
      return false if Resque.size(key) > 0
    end
    true
  end
  
  def self.flush_queues
    if Resque.redis
      Resque.queues.each do |key|
        Resque.redis.ltrim("queue:#{key}", 1, 0)
      end
    end
  end
end