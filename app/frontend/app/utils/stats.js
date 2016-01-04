import Ember from 'ember';
import CoughDrop from '../app';
import i18n from './i18n';

CoughDrop.Stats = Ember.Object.extend({
  no_data: function() {
    return this.get('total_sessions') === undefined || this.get('total_sessions') === 0;
  }.property('total_sessions'),
  popular_words: function() {
    return (this.get('words_by_frequency') || []).filter(function(word, idx) { return idx < 10 && word['count'] > 1; });
  }.property('words_by_frequency'),
  weighted_words: function() {
    var max = ((this.get('words_by_frequency') || [])[0] || {}).count || 0;
    var res = (this.get('words_by_frequency') || []).filter(function(word) { return !word.text.match(/^[\+:]/); }).map(function(word) {
      var weight = "weight_" + Math.ceil(word.count / max * 10);
      return {text: word.text, weight_class: "weighted_word " + weight};
    });
    return res.sort(function(a, b) { 
      var a_text = (a.text || "").toLowerCase();
      var b_text = (b.text || "").toLowerCase();
      if(a_text < b_text) { return -1; } else if(a_text > b_text) { return 1; } else { return 0; } 
    });
  }.property('words_by_frequency'),
  geo_locations: function() {
    return (this.get('locations') || []).filter(function(location) { return location.type == 'geo'; });
  }.property('locations'),
  ip_locations: function() {
    return (this.get('locations') || []).filter(function(location) { return location.type == 'ip_address'; });
  }.property('locations'),
  tz_offset: function() {
    return (new Date()).getTimezoneOffset();
  },
  local_time_blocks: function() {
    var new_blocks = {};
    var offset = this.tz_offset() / 15;
    var max = this.get('max_time_block');
    var blocks = this.get('time_offset_blocks');
    var mod = (7 * 24 * 4);
    for(var idx in blocks) {
      var new_block = (idx - offset + mod) % mod;
      new_blocks[new_block] = blocks[idx];
    }
    var res = [];
    for(var wday = 0; wday < 7; wday++) {
      var day = {day: wday, blocks: []};
      if(wday === 0) {
        day.day = i18n.t('sunday_abbrev', 'Su');
      } else if(wday == 1) {
        day.day = i18n.t('monday_abbrev', 'M');
      } else if(wday == 2) {
        day.day = i18n.t('tuesday_abbrev', 'Tu');
      } else if(wday == 3) {
        day.day = i18n.t('wednesday_abbrev', 'W');
      } else if(wday == 4) {
        day.day = i18n.t('thurs_abbrev', 'Th');
      } else if(wday == 5) {
        day.day = i18n.t('friday_abbrev', 'F');
      } else if(wday == 6) {
        day.day = i18n.t('saturday_abbrev', 'Sa');
      }
      for(var block = 0; block < (24*4); block = block + 2) {
        var val = new_blocks[(wday * 24 * 4) + block] || 0;
        val = val + (new_blocks[(wday * 24 * 4) + block + 1] || 0);
        var level = Math.ceil(val / max * 10);
        var hour = Math.floor(block / 4);
        var minute = (block % 4) === 0 ? ":00" : ":30";
        var tooltip = day.day + " " + hour + minute + ", ";
        tooltip = tooltip + i18n.t('n_events', "event", {hash: {count: val}});
        day.blocks.push({
          val: val,
          tooltip: val ? tooltip : "",
          style_class: val ? ("time_block level_" + level) : "time_block"
        });
      }
      res.push(day);
    }
    return res;
  }.property('time_offset_blocks', 'max_block'),
  start_date_field: function() {
    return (this.get('start_at') || "").substring(0, 10);
  }.property('start_at'),
  end_date_field: function() {
    return (this.get('end_at') || "").substring(0, 10);
  }.property('end_at')
});

export default CoughDrop.Stats;