import Ember from 'ember';
import i18n from '../../utils/i18n';

export default Ember.Route.extend({
  model: function(params) {
    return this.modelFor('board');
  },
  setupController: function(controller, model) {
    controller.set('key', model.get('lookup_key'));
    controller.load_results();
  }
});
