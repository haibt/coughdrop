import modal from '../utils/modal';
import capabilities from '../utils/capabilities';

export default modal.ModalController.extend({
  non_https: function() {
    return (this.get('model.url') || '').match(/^http:/);
  }.property('model.url'),
  actions: {
    open_link: function() {
      modal.close();
      capabilities.window_open(this.get('model.real_url') || this.get('model.url'), '_blank');
    }
  }
});
