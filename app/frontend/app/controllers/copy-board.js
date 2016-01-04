import Ember from 'ember';
import CoughDrop from '../app';
import modal from '../utils/modal';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    this.set('model.jump_home', true);
    this.set('model.keep_as_self', false);
    var supervisees = [];
    if(app_state.get('sessionUser.supervisees')) {
      app_state.get('sessionUser.supervisees').forEach(function(supervisee) {
        var res = Ember.Object.create(supervisee);
        res.set('currently_speaking', app_state.get('currentUser.id') == supervisee.id);
        res.set('disabled', !supervisee.edit_permission);
        supervisees.push(res);
      });
      this.set('currently_selected_id', null);
    } else {
      this.set('currently_selected_id', 'self');
    }
    this.set('model.supervisees', supervisees);
  },
  linked: function() {
    return (this.get('model.board.linked_boards') || []).length > 0;
  }.property('model.board.buttons'),
  user_board: function() {
    var for_user_id = this.get('currently_selected_id');
    this.set('self_currently_selected', for_user_id == 'self');
    if(this.get('model.supervisees')) {
      this.get('model.supervisees').forEach(function(sup) {
        if(for_user_id == sup.id) {
          sup.set('currently_selected', true);
        } else {
          sup.set('currently_selected', false);
        }
      });
    }
    if(for_user_id) {
      var _this = this;
      this.set('loading', true);
      this.set('error', false);
      this.set('current_user', null);
      var find_user = CoughDrop.store.findRecord('user', for_user_id).then(function(user) {
        if(!user.get('stats')) {
          return user.reload();
        } else {
          return user;
        }
      });
      find_user.then(function(user) {
        var in_board_set = (user.get('stats.board_set_ids') || []).indexOf(_this.get('model.board.id')) >= 0;
        _this.set('current_user', user);
        _this.set('loading', false);
        _this.set('in_board_set', !!in_board_set);
      }, function() {
        _this.set('loading', false);
        _this.set('error', true);
      });
    } else {
      this.set('loading', false);
      this.set('error', false);
      this.set('in_board_set', false);
    }
  }.observes('currently_selected_id', 'model.supervisees'),
  actions: {
    tweakBoard: function(decision) {
      if(this.get('model.supervisees').length > 0) {
        if(!this.get('currently_selected_id')) {
          return;
        }
      }
      var shares = [];

      if(this.get('self_currently_selected')) {
        (this.get('model.supervisees') || []).forEach(function(sup) {
          if(sup.share) {
            shares.push(sup);
          }
        });
      }
      modal.close({action: decision, user: this.get('current_user'), shares: shares});
    },
    close: function() {
      modal.close(false);
    },
    select: function(for_user_id) {
      this.set('currently_selected_id', for_user_id);
    }
  }
});
