# https://developers.google.com/maps/documentation/javascript/tutorial
# http://stackoverflow.com/questions/19304574/center-set-zoom-of-map-to-cover-all-markers-visible-markers

module Stats
  def self.cached_daily_use(user_id, options)
    user = User.find_by_global_id(user_id)
    if !user || WeeklyStatsSummary.where(:user_id => user.id).count == 0
      return daily_use(user_id, options)
    end
    sanitize_find_options!(options)
    week_start = options[:start_at].utc.beginning_of_week(:sunday)
    week_end = options[:end_at].utc.end_of_week(:sunday)
    start_weekyear = (options[:start_at].utc.to_date.cwyear * 100) + options[:start_at].utc.to_date.cweek
    end_weekyear = (options[:end_at].utc.to_date.cwyear * 100) + options[:end_at].utc.to_date.cweek
    summaries = WeeklyStatsSummary.where(['user_id = ? AND weekyear >= ? AND weekyear <= ?', user.id, start_weekyear, end_weekyear])
    summary_lookups = {}
    summaries.each{|s| summary_lookups[s.weekyear] = s }

    days = {}
    all_stats = []
    options[:start_at].to_date.upto(options[:end_at].to_date) do |date|
      weekyear = (date.cwyear * 100) + date.cweek
      summary = summary_lookups[weekyear]
      day = summary && summary.data && summary.data['stats']['days'][date.to_s]
      filtered_day_stats = nil
      if day
        filtered_day_stats = [day['total']]
        if options[:device_ids] || options[:location_ids]
          groups = day['group_counts'].select do |group|
            (!options[:device_ids] || options[:device_ids].include?(group['device_id'])) && 
            (!options[:location_ids] || options[:location_ids].include?(group['geo_cluster_id']) || options[:location_ids].include?(group['ip_cluster_id']))
          end
          filtered_day_stats = groups
        end
      else
        filtered_day_stats = [Stats.stats_counts([])]
      end
      all_stats += filtered_day_stats
      days[date.to_s] = usage_stats(filtered_day_stats)
    end
    
    res = usage_stats(all_stats)
    res[:days] = days
    res[:start_at] = options[:start_at].to_time.utc.iso8601
    res[:end_at] = options[:end_at].to_time.utc.iso8601
    res[:cached] = true
    res
  end
  
  # TODO: this doesn't account for timezones at all. wah waaaaah.
  def self.daily_use(user_id, options)
    sessions = find_sessions(user_id, options)
    
    total_stats = init_stats(sessions)
    total_stats.merge!(time_block_use_for_sessions(sessions))
    days = {}
    options[:start_at].to_date.upto(options[:end_at].to_date) do |date|
      day_sessions = sessions.select{|s| s.started_at.to_date == date }
      day_stats = stats_counts(day_sessions, total_stats)
      day_stats.merge!(time_block_use_for_sessions(day_sessions))
      
      # TODO: cache this day object, maybe in advance
      days[date.to_s] = usage_stats(day_stats)
    end
    res = usage_stats(total_stats)
    
    res.merge!(touch_stats(sessions))
    res.merge!(device_stats(sessions))
    res.merge!(parts_of_speech_stats(sessions))
    
    res[:days] = days

    res[:locations] = location_use_for_sessions(sessions)
    res[:start_at] = options[:start_at].to_time.utc.iso8601
    res[:end_at] = options[:end_at].to_time.utc.iso8601
    res
    # collect all matching sessions
    # build a stats object based on all sessions including:
    # - total utterances
    # - average words per utterance
    # - average buttons per utterance
    # - total buttons
    # - most popular words
    # - most popular boards
    # - total button presses per day
    # - unique button presses per day
    # - button presses per day per button (top 20? no, because we need this to figure out words they're using more or less than before)
    # - buttons per minute during an active session
    # - utterances per minute (hour?) during an active session
    # - words per minute during an active session
    # TODO: need some kind of baseline to compare against, a milestone model of some sort
    # i.e. someone presses "record baseline" and stats can used the newest baseline before start_at
    # or maybe even baseline_id can be set as a stats option -- ooooooooh...
  end
  
  # TODO: TIMEZONES
  def self.hourly_use(user_id, options)
    sessions = find_sessions(user_id, options)

    total_stats = init_stats(sessions)
    
    hours = []
    24.times do |hour_number|
      hour_sessions = sessions.select{|s| s.started_at.hour == hour_number }
      hour_stats = stats_counts(hour_sessions, total_stats)
      hour = usage_stats(hour_stats)
      hour[:hour] = hour_number
      hour[:locations] = location_use_for_sessions(hour_sessions)
      hours << hour
    end
    
    res = usage_stats(total_stats)
    res[:hours] = hours

    res[:start_at] = options[:start_at].to_time.utc.iso8601
    res[:end_at] = options[:end_at].to_time.utc.iso8601
    res
  end
  
  def self.board_use(board_id, options)
    board = Board.find_by_global_id(board_id)
    if !board
      return {
        :uses => 0,
        :home_uses => 0,
        :stars => 0,
        :forks => 0,
        :popular_forks => []
      }
    end
    res = {}
    # number of people using in their board set
    res[:uses] = board.settings['uses']
    # number of people using as their home board
    res[:home_uses] = board.settings['home_uses']
    # number of stars
    res[:stars] = board.stars
    # number of forks
    res[:forks] = board.settings['forks']
    # popular copies
    boards = Board.where(:parent_board_id => board.id).sort_by{|b| b.settings['popularity'] }.select{|b| b.settings['uses'] > 10 }.reverse[0, 5]
    res[:popular_forks] = boards.map{|b| JsonApi::Board.as_json(b) }
    # TODO: total uses over time
    # TODO: uses of each button over time
    res
  end

  def self.median(list)
    sorted = list.sort
    len = sorted.length
    return (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
  end
  
  def self.device_stats(sessions)
    res = []
    sessions.group_by(&:device).each do |device, device_sessions|
      next unless device
      stats = {}
      stats[:id] = device.global_id
      stats[:name] = device.settings['name'] || "Unspecified device"
      stats[:last_used_at] = device.last_used_at.iso8601
      stats[:total_sessions] = device_sessions.length
      started = device_sessions.map(&:started_at).compact.min
      stats[:started_at] = started && started.iso8601
      ended = device_sessions.map(&:ended_at).compact.max
      stats[:ended_at] = ended && ended.iso8601

      res << stats
    end
    res = res.sort_by{|r| r[:total_sessions] }.reverse
    {:devices => res}
  end

  def self.touch_stats(sessions)
    counts = {}
    max = 0
    sessions.each do |session|
      (session.data['touch_locations'] || {}).each do |board_id, xs|
        xs.each do |x, ys|
          ys.each do |y, count|
            counts[x.to_s + "," + y.to_s] ||= 0
            counts[x.to_s + "," + y.to_s] += count
            max = [max, counts[x.to_s + "," + y.to_s]].max
          end
        end
      end
    end
    {:touch_locations => counts, :max_touches => max}
  end

  def self.usage_stats(stats_list)
    return unless stats_list
    stats_list = [stats_list] if !stats_list.is_a?(Array)
    
    res = {
      :total_sessions => 0,
      :total_utterances => 0,
      :words_per_utterance => 0.0,
      :buttons_per_utterance => 0.0,
      :total_buttons => 0,
      :unique_buttons => 0,
      :total_words => 0,
      :unique_words => 0,
      :words_by_frequency => [],
      :buttons_by_frequency => [],
      :words_per_minute => 0.0,
      :buttons_per_minute => 0.0,
      :utterances_per_minute => 0.0
    }
    
    total_utterance_words = 0
    total_utterance_buttons = 0
    total_utterances = 0
    total_session_seconds = 0
    total_words = 0
    total_buttons = 0
    all_button_counts = {}
    all_word_counts = {}
    all_devices = nil
    all_locations = nil

    stats_list.each do |stats|
      stats = stats.with_indifferent_access
      # TODO: should we be calculating EVERYTHING off of only uttered content?
      buttons = stats[:all_button_counts].map{|k, v| v['count'] }.sum
      words = stats[:all_word_counts].map{|k, v| v }.sum
      total_buttons += buttons
      total_words += words
      total_utterance_words += stats[:total_utterance_words] if stats[:total_utterance_words]
      total_utterance_buttons += stats[:total_utterance_buttons] if stats[:total_utterance_buttons]
      total_utterances += stats[:total_utterances] if stats[:total_utterances]
      total_session_seconds += stats[:total_session_seconds] if stats[:total_session_seconds]
      
      res[:total_sessions] += stats[:total_sessions]
      res[:total_utterances] += stats[:total_utterances]
      res[:total_buttons] += buttons
      res[:unique_buttons] += stats[:all_button_counts].keys.length
      res[:total_words] += words
      res[:unique_words] += stats[:all_word_counts].keys.length
      res[:started_at] = [res[:started_at], stats[:started_at]].compact.min
      res[:ended_at] = [res[:ended_at], stats[:ended_at]].compact.max
      stats[:all_button_counts].each do |ref, button|
        if all_button_counts[ref]
          all_button_counts[ref]['count'] += button['count']
        else
          all_button_counts[ref] = button.merge({})
        end
      end
      stats[:all_word_counts].each do |word, cnt|
        all_word_counts[word] ||= 0
        all_word_counts[word] += cnt
      end

      if stats[:touch_locations]
        res[:touch_locations] ||= {}
        stats[:touch_locations].each do |loc, cnt|
          res[:touch_locations][loc] ||= 0
          res[:touch_locations][loc] += cnt
        end
      end
      
      if stats[:timed_blocks]
        offset_blocks = time_offset_blocks(stats[:timed_blocks])
        res[:time_offset_blocks] ||= {}
        offset_blocks.each do |block, cnt|
          res[:time_offset_blocks][block] ||= 0
          res[:time_offset_blocks][block] += cnt
        end
      end
      if stats[:parts_of_speech]
        stats[:parts_of_speech].each do |key, cnt|
          res[:parts_of_speech] ||= {}
          res[:parts_of_speech][key] ||= 0
          res[:parts_of_speech][key] += cnt
        end
      end
      if stats[:parts_of_speech_combinations]
        res[:parts_of_speech_combinations] ||= {}
        stats[:parts_of_speech_combinations].each do |key, cnt|
          res[:parts_of_speech_combinations][key] ||= 0
          res[:parts_of_speech_combinations][key] += cnt
        end
      end
      if stats[:devices]
        all_devices ||= {}
        stats[:devices].each do |device|
          if all_devices[device['id']]
            all_devices[device['id']]['total_sessions'] += device['total_sessions']
            all_devices[device['id']]['started_at'] = [all_devices[device['id']]['started_at'], device['started_at']].compact.min
            all_devices[device['id']]['ended_at'] = [all_devices[device['id']]['ended_at'], device['ended_at']].compact.max
          else
            all_devices[device['id']] = device.merge({})
          end
        end
      end
      if stats[:locations]
        all_locations ||= {}
        stats[:locations].each do |location|
          if all_locations[location['id']]
            all_locations[location['id']]['total_sessions'] += location['total_sessions']
            all_locations[location['id']]['started_at'] = [all_locations[location['id']]['started_at'], location['started_at']].compact.min
            all_locations[location['id']]['ended_at'] = [all_locations[location['id']]['ended_at'], location['ended_at']].compact.max
          else
            all_locations[location['id']] = location.merge({})
          end
        end
      end
    end
    if all_devices
      res[:devices] = all_devices.map(&:last)
    end
    if all_locations
      res[:locations] = all_locations.map(&:last)
    end
    if res[:touch_locations]
      res[:max_touches] = res[:touch_locations].map(&:last).max
    end
    if res[:time_offset_blocks]
      res[:max_time_block] = res[:time_offset_blocks].map(&:last).max
    end
    res[:words_per_utterance] += total_utterances > 0 ? (total_utterance_words / total_utterances) : 0.0
    res[:buttons_per_utterance] += total_utterances > 0 ? (total_utterance_buttons / total_utterances) : 0.0
    res[:words_per_minute] += total_session_seconds > 0 ? (total_words / total_session_seconds * 60) : 0.0
    res[:buttons_per_minute] += total_session_seconds > 0 ? (total_buttons / total_session_seconds * 60) : 0.0
    res[:utterances_per_minute] +=  total_session_seconds > 0 ? (total_utterances / total_session_seconds * 60) : 0.0
    res[:buttons_by_frequency] = all_button_counts.to_a.sort_by{|ref, button| [button['count'], button['text']] }.reverse.map(&:last)[0, 50]
    res[:words_by_frequency] = all_word_counts.to_a.sort_by{|word, cnt| [cnt, word] }.reverse.map{|word, cnt| {'text' => word, 'count' => cnt} }[0, 100]
    
    res
  end
  
  def self.stats_counts(sessions, total_stats_list=nil)
    stats = init_stats(sessions)
    sessions.each do |session|
      if session.data['stats']
        # TODO: more filtering needed for board-specific drill-down
        stats[:total_session_seconds] += session.data['stats']['session_seconds'] || 0
        stats[:total_utterances] += session.data['stats']['utterances'] || 0
        stats[:total_utterance_words] += session.data['stats']['utterance_words'] || 0
        stats[:total_utterance_buttons] += session.data['stats']['utterance_buttons'] || 0
        (session.data['stats']['all_button_counts'] || []).each do |ref, button|
          if stats[:all_button_counts][ref]
            stats[:all_button_counts][ref]['count'] += button['count']
          else
            stats[:all_button_counts][ref] = button.merge({})
          end
        end
        (session.data['stats']['all_word_counts'] || []).each do |word, cnt|
          stats[:all_word_counts][word] ||= 0
          stats[:all_word_counts][word] += cnt
        end
      end
    end
    starts = sessions.map(&:started_at).compact.sort
    ends = sessions.map(&:ended_at).compact.sort
    stats[:started_at] = starts.length > 0 ? starts.first.utc.iso8601 : nil
    stats[:ended_at] = ends.length > 0 ? ends.last.utc.iso8601 : nil
    if total_stats_list
      total_stats_list = [total_stats_list] unless total_stats_list.is_a?(Array)
      total_stats_list.each do |total_stats|
        total_stats[:total_utterances] += stats[:total_utterances]
        total_stats[:total_utterance_words] += stats[:total_utterance_words]
        total_stats[:total_utterance_buttons] += stats[:total_utterance_buttons]
        total_stats[:total_session_seconds] += stats[:total_session_seconds]
        stats[:all_button_counts].each do |ref, button|
          if total_stats[:all_button_counts][ref]
            total_stats[:all_button_counts][ref]['count'] += button['count']
          else
            total_stats[:all_button_counts][ref] = button.merge({})
          end
        end
        stats[:all_word_counts].each do |word, cnt|
          total_stats[:all_word_counts][word] ||= 0
          total_stats[:all_word_counts][word] += cnt
        end
        total_stats[:started_at] = [total_stats[:started_at], stats[:started_at]].compact.sort.first
        total_stats[:ended_at] = [total_stats[:ended_at], stats[:ended_at]].compact.sort.last
      end
    end
    stats
  end
  
  def self.init_stats(sessions)
    stats = {}
    stats[:total_sessions] = sessions.length
    stats[:total_utterances] = 0.0
    stats[:total_utterance_words] = 0.0
    stats[:total_utterance_buttons] = 0.0
    stats[:total_session_seconds] = 0.0
    stats[:all_button_counts] = {}
    stats[:all_word_counts] = {}
    stats
  end
  
  def self.sanitize_find_options!(options)
    options[:end_at] = options[:end_at] || (Date.parse(options[:end]) rescue nil)
    options[:start_at] = options[:start_at] || (Date.parse(options[:start]) rescue nil)
    options[:end_at] ||= Time.now + 1000
    end_time = (options[:end_at].to_date + 1).to_time
    options[:end_at] = (end_time + end_time.utc_offset - 1).utc
    options[:start_at] ||= (options[:end_at]).to_date << 2 # limit by date range
    options[:start_at] = options[:start_at].to_time.utc
    if options[:end_at].to_time - options[:start_at].to_time > 6.months.to_i
      raise(StatsError, "time window cannot be greater than 6 months")
    end
    options[:device_ids] = [options[:device_id]] if !options[:device_id].blank? # limit to a list of devices
    options[:device_ids] = nil if options[:device_ids].blank?
    options[:board_ids] = [options[:board_id]] if !options[:board_id].blank? # limit to a single board (this is not board-level stats, this is user-level drill-down)
    options[:board_ids] = nil if options[:device_ids].blank?
    options[:location_ids] = [options[:location_id]] if !options[:location_id].blank? # limit to a single geolocation or ip address
    options[:location_ids] = nil if options[:location_ids].blank?
  end
  
  def self.find_sessions(user_id, options)
    sanitize_find_options!(options)
    user = user_id && User.find_by_global_id(user_id)
    raise(StatsError, "user not found") unless user
    sessions = LogSession.where(['user_id = ? AND started_at > ? AND ended_at < ?', user.id, options[:start_at], options[:end_at]])
    if options[:device_ids]
      devices = Device.find_all_by_global_id(options[:device_ids]).select{|d| d.user_id == user.id }
      sessions = sessions.where(:device_id => devices.map(&:id))
    end
    if options[:location_ids]
      # TODO: supporting multiple locations is slightly trickier than multiple devices
      cluster = ClusterLocation.find_by_global_id(options[:location_ids][0])
      raise(StatsError, "cluster not found") unless cluster && cluster.user_id == user.id
      if cluster.ip_address?
        sessions = sessions.where(:ip_cluster_id => cluster.id)
      elsif cluster.geo?
        sessions = sessions.where(:geo_cluster_id => cluster.id)
      else
        raise(StatsError, "this should never be reached")
      end
    end
    if options[:board_ids]
      sessions = sessions.select{|s| s.has_event_for_board?(options[:board_id]) }
    end
    sessions
  end
  
  def self.location_use_for_sessions(sessions)
    geo_ids = sessions.map(&:geo_cluster_id).compact.uniq
    ip_ids = sessions.map(&:ip_cluster_id).compact.uniq
    res = []
    return res unless geo_ids.length > 0 || ip_ids.length > 0
    ClusterLocation.where(:id => (geo_ids + ip_ids)).each do |cluster|
      cluster_sessions = sessions.select{|s| s.ip_cluster_id == cluster.id || s.geo_cluster_id == cluster.id }

      location = {}
      location[:id] = cluster.global_id
      location[:type] = cluster.cluster_type
      location[:total_sessions] = cluster_sessions.length
      started = cluster_sessions.map(&:started_at).compact.min
      location[:started_at] = started && started.iso8601
      ended = cluster_sessions.map(&:ended_at).compact.max
      location[:ended_at] = ended && ended.iso8601

      if cluster.ip_address?
        location[:readable_ip_address] = cluster.data['readable_ip_address']
        location[:ip_address] = cluster.data['ip_address']
      end
      if cluster.geo?
        location[:geo] = {
          :latitude => cluster.data['geo'][0],
          :longitude => cluster.data['geo'][1],
          :altitude => cluster.data['geo'][2]
        }
      end
      res << location
    end
    res
  end
  
  def self.parts_of_speech_stats(sessions)
    parts = {}
    sequences = {}
    sessions.each do |session|
      (session.data['stats']['parts_of_speech'] || {}).each do |part, cnt|
        parts[part] ||= 0
        parts[part] += cnt
      end
      
      prior_parts = []
      session.data['events'].each do |event|
        if event['type'] == 'action' && event['action'] == 'clear'
          prior_parts = []
        elsif event['type'] == 'utterance'
          prior_parts = []
        elsif event['modified_by_next']
        else
          if event['parts_of_speech']
            current_part = event['parts_of_speech']
            if prior_parts[-1] && prior_parts[-2]
              from_from = prior_parts[-2]['types'][0]
              from = prior_parts[-1]['types'][0]
              to = current_part['types'][0]
              sequences[from_from + "," + from + "," + to] ||= 0
              sequences[from_from + "," + from + "," + to] += 1
              sequences[from_from + "," + from] -= 1 if sequences[from_from + "," + from]
              sequences.delete(from_from + "," + from) if sequences[from_from + "," + from] == 0
              sequences[from + "," + to] ||= 0
              sequences[from + "," + to] += 1
            elsif prior_parts[-1]
              from = prior_parts[-1]['types'][0]
              to = current_part['types'][0]
              sequences[from + "," + to] ||= 0
              sequences[from + "," + to] += 1
            end
          end
          prior_parts << event['parts_of_speech']
        end
      end
    end
    {:parts_of_speech => parts, :parts_of_speech_combinations => sequences}
  end
  
  TIMEBLOCK_MOD = 7 * 24 * 4
  TIMEBLOCK_OFFSET = 4 * 24 * 4
  def self.time_block(timestamp)
    ((timestamp.to_i / 60 / 15) + TIMEBLOCK_OFFSET) % TIMEBLOCK_MOD
  end
  
  def self.time_offset_blocks(timed_blocks)
    blocks = {}
    timed_blocks.each do |blockstamp, cnt|
      block = time_block(blockstamp.to_i * 15)
      blocks[block] ||= 0
      blocks[block] += cnt
    end
    max = blocks.map(&:last).max
    blocks
  end
  
  def self.time_block_use_for_sessions(sessions)
    timed_blocks = {}
    sessions.each do |session|
      (session.data['events'] || []).each do |event|
        next unless event['timestamp']
        timed_block = event['timestamp'].to_i / 15
        timed_blocks[timed_block] ||= 0
        timed_blocks[timed_block] += 1
      end
    end
    {:timed_blocks => timed_blocks, :max_time_block => timed_blocks.map(&:last).max }
  end

  # TODO: someday start figuring out word complexity and word type for buttons and utterances
  # i.e. how many syllables, applied tenses/modifiers, nouns/verbs/adjectives/etc.
  
  
  def self.lam(sessions)
    res = lam_header
    sessions.each do |session|
      res += lam_entries(session)
    end
    res
  end
  
  def self.lam_header
    lines = []
    lines << "### CAUTION ###"
    lines << "The following data represents an individual's communication"
    lines << "and should be treated accordingly."
    lines << ""
    lines << "LAM Content generated by CoughDrop AAC app"
    lines << "LAM Version 2.00 07/26/01"
    lines << ""
    lines << ""
    lines.join("\n")
  end
  
  def self.lam_entries(session)
    lines = []
    date = nil
    (session.data['events'] || []).each do |event|
      # TODO: timezones
      time = Time.at(event['timestamp'])
      stamp = time.strftime("%H:%M:%S")
      if !date || time.to_date != date
        date = time.to_date
        date_stamp = date.strftime('%y-%m-%d')
        lines << "#{stamp} CTL *[YY-MM-DD=#{date_stamp}]*"
      end
      if event['button']
        if event['button']['completion']
          lines << "#{stamp} WPR \"#{event['button']['completion']}\""
        elsif event['button']['vocalization'] && event['button']['vocalization'].match(/^\+/)
          lines << "#{stamp} SPE \"#{event['button']['vocalization'][1..-1]}\""
        elsif event['button']['label'] && (!event['button']['vocalization'] || !event['button']['vocalization'].match(/^:/))
          # TODO: need to confirm, but it seems like if the user got to the word from a 
          # link, that would be qualify as semantic compaction instead of
          # a single-meaning picture...
          lines << "#{stamp} SMP \"#{event['button']['label']}\""
        end
      end
    end
    lines.join("\n") + "\n"
  end
  
  class StatsError < StandardError; end
end