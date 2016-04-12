import Ember from 'ember';
import i18n from './i18n';
import CoughDrop from '../app';
import editManager from './edit_manager';
import persistence from './persistence';
import coughDropExtras from './extras';
import modal from './modal';
import stashes from './_stashes';
import app_state from './app_state';
import progress_tracker from './progress_tracker';

var contentGrabbers = Ember.Object.extend({
  setup: function(button, controller) {
    this.controller = controller;
    pictureGrabber.setup(button, controller);
    soundGrabber.setup(button, controller);
    boardGrabber.setup(button, controller);
    linkGrabber.setup(button, controller);
  },
  clear: function() {
    pictureGrabber.clear();
    soundGrabber.clear();
    boardGrabber.clear();
    linkGrabber.clear();
  },
  unlink: function() {
    pictureGrabber.controller = null;
    pictureGrabber.button = null;
    soundGrabber.controller = null;
    soundGrabber.button = null;
    boardGrabber.controller = null;
    boardGrabber.button = null;
  },
  save_record: function(object) {
    var _this = this;
    var promise = new Ember.RSVP.Promise(function(resolve, reject) {
      if((object.get('url') || "").match(/^data:/)) {
        object.set('data_url', object.get('url'));
        object.set('url', null);
      }
      var original = object;
      object.save().then(function(object) {
        if(!object.get('url') && object.get('data_url')) {
          object.set('url', object.get('data_url'));
        }
        if(object.get('pending')) {
          var meta = persistence.meta(object.constructor.modelName, null); //object.store.metadataFor(object.constructor.modelName);
          if(!meta || !meta.remote_upload) { return reject({error: 'remote_upload parameters required'}); }
          // upload to S3
          meta.remote_upload.data_url = object.get('data_url');
          _this.upload_to_remote(meta.remote_upload).then(function(data) {
            if(data.confirmed) {
              object.set('url', data.url);
              object.set('pending', false);
              resolve(object);
            } else {
              reject({error: "upload not confirmed"});
            }
          }, function(err) {
            reject(err);
          });
        } else {
          resolve(object);
        }
      }, function(err) { reject({error: "record failed to save", ref: err}); });
    });
    return promise;
  },
  upload_to_remote: function(params) {
    var _this = this;
    var promise = new Ember.RSVP.Promise(function(resolve, reject) {
      var fd = new FormData();
      for(var idx in params.upload_params) {
        fd.append(idx, params.upload_params[idx]);
      }
      fd.append('file', _this.data_uri_to_blob(params.data_url));

      persistence.ajax({
        url: params.upload_url,
        type: 'POST',
        data: fd,
        processData: false,  // tell jQuery not to process the data
        contentType: false   // tell jQuery not to set contentType
      }).then(function(data) {
        var method = params.success_method || 'GET';
        persistence.ajax({
          url: params.success_url,
          type: method
        }).then(function(data) {
          resolve(data);
        }, function(err) {
          reject({error: "upload not completed"});
        });
      }, function(err) {
        reject({error: "upload failed"});
      });
    });
    return promise;
  },
  data_uri_to_blob: function(data_uri) {
    var pre = data_uri.split(/;/)[0];
    var type = pre.split(/:/)[1];
    var binary = atob(data_uri.split(',')[1]);
    var array = [];
    for(var i = 0; i < binary.length; i++) {
        array.push(binary.charCodeAt(i));
    }
    return new Blob([new Uint8Array(array)], {type: type});
  },
  file_dropped: function(id, type, file) {
    this.droppedFile = {
      type: type,
      file: file
    };

    var state = type == 'image' ? 'picture' : 'sound';
    this.board_controller.send('buttonSelect', id, state);
  },
  check_for_dropped_file: function() {
    var drop = this.droppedFile;
    this.droppedFile = null;
    if(drop) {
      if(drop.file.url) {
        pictureGrabber.web_image_dropped(drop);
      } else {
        if(drop.type == 'image') {
          pictureGrabber.file_selected(drop.file);
        } else {
          soundGrabber.file_selected(drop.file);
        }
      }
    }
  },
  file_selected: function(type, files) {
    var image = null, sound = null, board = null;
    for(var idx = 0; idx < files.length; idx++) {
      if(!image && files[idx].type.match(/^image/)) {
        image = files[idx];
      } else if(!sound && files[idx].type.match(/^audio/)) {
        sound = files[idx];
      } else {
        if(!board && files[idx].name.match(/\.(obf|obz)$/)) {
          board = files[idx];
        }
      }
    }
    if(type == 'image' || type == 'avatar') {
      if(image) {
        pictureGrabber.file_selected(image, type);
      } else {
        alert(i18n.t('no_valid_image_found', "No valid image found"));
      }
    } else if(type == 'sound') {
      if(sound) {
        soundGrabber.file_selected(sound);
      } else {
        alert(i18n.t('no_valid_sound_found', "No valid sound found"));
      }
    } else if(type == 'board') {
      boardGrabber.file_selected(board);
    } else {
      alert(i18n.t('bad_file', "bad file"));
    }
  },
  content_dropped: function(button_id, dataTransfer) {
    if(!app_state.get('edit_mode') || !dataTransfer) { return; }
    if(dataTransfer.files && dataTransfer.files.length > 0) {
      var files = dataTransfer.files;
      var image = null, sound = null;
      for(var idx = 0; idx < files.length; idx++) {
        if(!image && files[idx].type.match(/^image/)) {
          image = files[idx];
        } else if(!sound && files[idx].type.match(/^audio/)) {
          sound = files[idx];
        }
      }
      if(image) {
        contentGrabbers.file_dropped(button_id, 'image', image);
      } else if(sound) {
        contentGrabbers.file_dropped(button_id, 'sound', sound);
      } else {
        alert(i18n.t('no_valid_files', "No valid images or sounds found"));
      }
    } else if(dataTransfer.items && dataTransfer.items.length > 0) {
      var found = false;
      var callback = function(url) {
        contentGrabbers.file_dropped(button_id, 'image', {url: url});
      };
      for(var idx = 0; idx < dataTransfer.types.length; idx++) {
        if(!found && dataTransfer.types[idx] == 'text/uri-list') {
          found = true;
          dataTransfer.items[idx].getAsString(callback);
        }
      }
      if(!found) {
        alert(i18n.t('unrecognized_drop_type', "Unrecognized drop type"));
      }
    } else {
      alert(i18n.t('unrecognized_drop_type', "Unrecognized drop type"));
    }
  },
  read_file: function(file) {
    return new Ember.RSVP.Promise(function(resolve, reject) {
      var reader = new FileReader();
      var _this = this;
      reader.onload = function(data) {
        Ember.run(function() {
          resolve(data);
        });
      };
      reader.readAsDataURL(file);
    });
  },
  save_pending: function() {
    soundGrabber.save_pending();
    var _this = this;
    // the returned promise isn't saying everything is done saving, just that
    // essential information held in an iframe in the settings modal.
    return editManager.get_edited_image().then(function(data) {
      pictureGrabber.edited_image_data = data;
      pictureGrabber.save_pending();
      return {ready: true};
    }, function() {
      pictureGrabber.edited_image_data = null;
      pictureGrabber.save_pending();
      return Ember.RSVP.resolve({ready: true});
    });
  },
  file_type_extensions: {
    'image/png': '.png',
    'image/svg+xml': '.xvg',
    'image/gif': '.gif',
    'image/x-icon': '.ico',
    'image/jpeg': '.jpg',
    'image/jpg': '.jpg',
    'image/tiff': '.tif',
    'image/x-tiff': '.tif',
    'audio/mpeg': '.mp2',
    'audio/midi': '.mid',
    'audio/x-mid': '.mid',
    'audio/x-midi': '.mid',
    'audio/x-mpeg': '.mp2',
    'audio/mpeg3': '.mp3',
    'audio/x-mpeg3': '.mp3',
    'audio/wav': '.wav',
    'audio/x-wav': '.wav',
    'audio/ogg': '.oga',
    'audio/flac': '.flac',
    'audio/webm': '.webm'

  }
}).create();
var pictureGrabber = Ember.Object.extend({
  setup: function(button, controller) {
    this.controller = controller;
    this.button = button;
    var _this = this;
    Ember.run.later(function() {
      button.findContentLocally().then(function() {
        var image = button.get('image');
        if(image) {
          image.check_for_editable_license();
        }
      });
    });
    _this.controller.addObserver('image_preview', _this, _this.default_image_preview_license);
  },
  default_size: 300,
  size_image: function(data_url, stored_size) {
    var _this = this;
    return new Ember.RSVP.Promise(function(resolve, reject) {
      if(data_url.match(/^http/)) { return resolve({url: data_url}); }
      if(!window.scratch_canvas) {
        window.scratch_canvas = document.createElement('canvas');
      }
      window.scratch_canvas.width = stored_size || _this.default_size;
      window.scratch_canvas.height = stored_size || _this.default_size;

      var context = window.scratch_canvas.getContext('2d');
      var img = document.createElement('img');
      var result = null;
      var canvas = window.scratch_canvas;
      img.onload = function() {
        Ember.run(function() {
          if(img.width < _this.default_size && img.height < _this.default_size) {
            return resolve({url: data_url, width: img.width, height: img.height});
          }
          var pct = img.width / img.height;
          var width = canvas.width, height = canvas.height, x = 0, y = 0;
          // TODO: is it actually good to have them all square? some button dimensions
          // would actually prefer non-square buttons if possible...
          if(pct > 1.0) {
            var diff = canvas.height - (canvas.height / pct);
            y = diff / 2.0;
            height = canvas.height - diff;
          } else {
            var diff = canvas.width - (canvas.width * pct);
            x = diff / 2.0;
            width = canvas.width - diff;
          }
          context.clearRect(0, 0, canvas.width, canvas.height);
          console.log(x + "," + y + "  " + width + "x" + height);
          context.drawImage(img, x, y, width, height);
          try {
            result = canvas.toDataURL();
          } catch(e) { }
          if(result) {
            resolve({url: result, width: canvas.width, height: canvas.height});
          } else {
            resolve({url: data_url});
          }
        });
      };
      img.onready = img.onload;
      img.onerror = function() {
        Ember.run(function() {
          resolve({url: data_url});
        });
      };
      img.src = data_url;
      if(img.width) {
        img.onload();
      }
    });
  },
  web_image_dropped: function(drop) {
    var _this = this;
    var sizer = pictureGrabber.size_image(drop.file.url);
    sizer.then(function(res) {
      var url = res.url;
      drop.file.url = url;
      _this.controller.set('model.image_field', drop.file.url);
      _this.find_picture(drop.file.url);
    });
  },
  file_selected: function(file, type) {
    var _this = this;
    var reader = contentGrabbers.read_file(file);
    if(type == 'avatar' && contentGrabbers.avatar_result) {
      contentGrabbers.avatar_result(true, 'loading');
    }
    var sizer = reader.then(function(data) {
      console.log(data.target.result);
      window.result = data.target.result;
      return pictureGrabber.size_image(data.target.result);
    });
    sizer.then(function(res) {
      var url = res.url;
      if(type == 'avatar') {
        var content_type = (url.split(/:/)[1] || "").split(/;/)[0];
        var image = CoughDrop.store.createRecord('image', {
          url: url,
          content_type: content_type,
          width: res.width || pictureGrabber.default_size,
          height: res.height || pictureGrabber.default_size,
          avatar: true,
          license: {
            type: 'private'
          }
        });
        contentGrabbers.save_record(image).then(function(res) {
          if(contentGrabbers.avatar_result) {
            contentGrabbers.avatar_result(true, res);
          } else {
            console.error("nothing to handle successful avatar upload");
          }
        }, function(err) {
          if(contentGrabbers.avatar_result) {
            contentGrabbers.avatar_result(false, err);
          } else {
            console.error("nothing to handle failed avatar upload");
          }
        });
      } else {
        _this.controller.set('image_preview', {
          url: url,
          name: file.name,
          editor: null
        });
      }
    });
  },
  clear: function() {
    this.clear_image_preview();
    this.controller.set('image_search', null);
    var stream = this.controller.get('webcam.stream');
    if(stream && stream.stop) {
      stream.stop();
    } else if(stream && stream.getVideoTracks) {
      stream.getVideoTracks().forEach(function(track) {
        track.stop();
      });
    }
    this.controller.set('webcam', null);
    Ember.$('#webcam_video').attr('src', '');
    Ember.$('#image_upload').val('');
  },
  clear_image_preview: function() {
    this.controller.set('image_preview', null);
  },
  default_image_preview_license: function() {
    var user = app_state.get('currentUser');
    if(user && this.controller.get('image_preview')) {
      if(!this.controller.get('image_preview.license')) {
       this.controller.set('image_preview.license', {type: 'private'});
      }
      if(!this.controller.get('image_preview.license.author_name') && this.controller.get('image_preview.license')) {
        this.controller.set('image_preview.license.author_name', user.get('user_name'));
      }
      if(!this.controller.get('image_preview.license.author_url') && this.controller.get('image_preview.license')) {
        this.controller.set('image_preview.license.author_url', user.get('profile_url'));
      }
    }
  },
  pick_preview: function(preview) {
    var license = {
      type: preview.license,
      copyright_notice_url: preview.license_url,
      source_url: preview.source_url,
      author_name: preview.author,
      author_url: preview.author_url,
      uneditable: true
    };
    this.controller.set('image_preview', {
      url: preview.image_url,
      search_term: this.controller.get('image_search.term'),
      external_id: preview.id,
      license: license
    });
  },
  find_picture: function(text) {
    if(text && (text.match(/^http/))) {
      var _this = this;
      _this.controller.set('image_search', null);
      persistence.ajax('/api/v1/search/proxy?url=' + encodeURIComponent(text), { type: 'GET'
      }).then(function(data) {
        _this.controller.set('image_preview', {
          url: data.data,
          content_type: data.content_type,
          source_url: text
        });
      }, function(xhr, message) {
        var error = i18n.t('not_available', "Image retrieval failed unexpectedly.");
        if(message && message.error == "not online") {
          error = i18n.t('not_online_image_proxy', "Cannot retrieve image, please connect to the Internet first.");
        }
        _this.controller.set('image_preview', {
          error: error
        });
      });
    } else if(text.match(/^data:/)) {
      this.controller.set('image_preview', {
        url: text
      });
      this.controller.set('image_search', null);
    } else {
      this.controller.set('image_preview', null);
      this.controller.set('image_search', {term: text});
      var _this = this;
      persistence.ajax('/api/v1/search/symbols?q=' + encodeURIComponent(text), { type: 'GET'
      }).then(function(data) {
        _this.controller.set('image_search.previews', data);
        _this.controller.set('image_search.previews_loaded', true);
      }, function(xhr, message) {
        var error = i18n.t('not_available', "Image retrieval failed unexpectedly.");
        if(message && message.error == "not online") {
          error = i18n.t('not_online_image_search', "Cannot search, please connect to the Internet first.");
        }
        _this.controller.set('image_search.error', error);
      });
    }
  },
  edit_image_preview: function() {
    var preview = this.controller.get('image_preview');
    var _this = this;

    (new Ember.RSVP.Promise(function(resolve, reject) {
      if(preview.url.match(/^http/)) {
        persistence.ajax('/api/v1/search/proxy?url=' + encodeURIComponent(preview.url), { type: 'GET'
        }).then(function(data) {
          resolve(data.data);
        }, function(xhr, message) {
          reject({error: "couldn't retrieve image data"});
        });
      } else {
        resolve(preview.url);
      }
    })).then(function(url) {
      editManager.stash_image({url: url});
      _this.controller.set('image_preview.editor', true);
    });
  },
  clear_image: function() {
    this.clear();
    this.controller.set('model.image', null);
  },
  edit_image: function() {
    var image = this.controller.get('model.image');

    var _this = this;
    var sizer = pictureGrabber.size_image(image.get('url'));
    sizer.then(function(res) {
      var url = res.url;
      _this.controller.set('image_preview', {
        url: url,
        content_type: image.get('content_type'),
        name: "",
        license: image.get('license'),
        editor: null
      });
      _this.edit_image_preview();
    });
  },
  select_image_preview: function(url) {
    var preview = this.controller && this.controller.get('image_preview');
    if(!preview || !preview.url) { return; }
    this.controller.set('model.pending_image', true);
    var _this = this;

    if(this.controller.get('image_preview.editor')) {
      if(!url) {
        if(_this.edited_image_data) {
          _this.select_image_preview(_this.edited_image_data);
        } else {
          editManager.get_edited_image().then(function(data) {
            _this.select_image_preview(data);
          }, function() {
          });
        }
        return;
      } else {
        preview.url = url;
      }
    }
    if(preview.url.match(/^data:/)) {
      preview.content_type = preview.content_type || preview.url.split(/;/)[0].split(/:/)[1];
    }
    if(!preview.license || !preview.license.copyright_notice_url) {
      Ember.set(preview, 'license', preview.license || {});
      var license_url = null;
      var licenses = CoughDrop.licenseOptions;
      for(var idx = 0; idx < licenses.length; idx++) {
        if(licenses[idx].id == preview.license.type) {
          license_url = licenses[idx].url;
        }
      }
      Ember.set(preview, 'license.copyright_notice_url', license_url);
    }
    var image_load = new Ember.RSVP.Promise(function(resolve, reject) {
      var i = new window.Image();
      i.onload = function() {
        resolve({
          width: i.width,
          height: i.height
        });
      };
      i.onerror = function() {
        reject({error: "image calculation failed"});
      };
      i.src = preview.url;
    });

    var save_image = image_load.then(function(data) {
      var image = CoughDrop.store.createRecord('image', {
        url: preview.url,
        content_type: preview.content_type,
        width: data.width,
        height: data.height,
        external_id: preview.external_id,
        search_term: preview.search_term,
        license: preview.license
      });
      var _this = this;
      return contentGrabbers.save_record(image);
    });
    save_image.then(function(image) {
      // TODO: if the image doesn't have a label yet, go ahead and set
      // it to the filename of this image pretty formatted (I guess also
      // strip off any trailing numbers).
      _this.controller.set('model.image', image);
      _this.clear();
      var button_image = {url: image.get('url'), id: image.id};
      editManager.change_button(_this.controller.get('model.id'), {
        'image': image,
        'image_id': image.id
      });
      _this.controller.set('model.pending_image', false);
    }).then(null, function(err) {
      err = err || {};
      err.error = err.error || "unexpected error";
      coughDropExtras.track_error("upload failed: " + err.error);
      alert(i18n.t('upload_failed', "upload failed:" + err.error));
      _this.controller.set('model.pending_image', false);
    });
  },
  save_pending: function() {
    var _this = this;
    if(this.controller.get('image_preview')) {
      this.select_image_preview();
    } else if(this.controller.get('model.image')) {
      var license = this.controller.get('model.image.license');
      var original = this.controller.get('original_image_license') || {};
      Ember.set(license, 'type', license.type || original.type);
      if(license.type != original.type || license.author_name != original.author_name || license.author_url != original.author_url) {
        this.controller.set('model.pending_image', false);
        this.controller.get('model.image').save().then(function() {
          _this.controller.set('model.pending_image', false);
        }, function() {
          alert(i18n.t('save_failed', "Saving settings failed!"));
          _this.controller.set('model.pending_image', false);
        });
      }
    }
  },
  webcam_available: function() {
    return !!(navigator.getUserMedia || (navigator.device && navigator.device.capture && navigator.device.capture.captureImage));
  },
  user_media_ready: function(stream, stream_id) {
    var video = document.querySelector('#webcam_video');
    var _this = this;
    if(video) {
      video.src = window.URL.createObjectURL(stream);
    }
    if(stream_id) {
      stashes.persist('last_stream_id', stream_id);
    }
    _this.clear_image_preview();
    _this.controller.set('image_search', null);
    _this.controller.set('webcam', {
      stream: stream,
      showing: true,
      stream_id: stream_id
    });
    if(window.MediaStreamTrack && window.MediaStreamTrack.getSources) {
      window.MediaStreamTrack.getSources(function(sources) {
        var video_streams = [];
        var source = null;
        for(var idx = 0; idx < sources.length; idx++) {
          source = sources[idx];
          if(source && source.kind == 'video') {
            video_streams.push({
              id: source.id,
              label: source.label || ('camera ' + (video_streams.length + 1))
            });
          }
        }
        // If there's nothing to swap out, don't bother telling anyone
        if(video_streams.length <= 1) {
          video_streams = [];
        }
        if(_this.controller.get('webcam')) {
          _this.controller.set('webcam.video_streams', video_streams);
        }
      });
    }
  },
  start_webcam: function() {
    var _this = this;
    // TODO: cross-browser
    if(navigator.getUserMedia) {
      var last_stream_id = stashes.get('last_stream_id');
      var constraints = {video: true};
      if(last_stream_id) {
        constraints.video = {
          optional: [{
            sourceId: last_stream_id
          }]
        };
      }
      navigator.getUserMedia(constraints, function(stream) {
        _this.user_media_ready(stream, last_stream_id);
      }, function() {
        console.log("permission not granted");
      });
    } else if(navigator.device && navigator.device.capture && navigator.device.capture.captureImage) {
      navigator.device.capture.captureImage(function(files) {
        var media_file = files[0];
        var file = new window.File(media_file.name, media_file.localURL, media_file.type, media_file.lastModifiedDate, media_file.size);
        _this.file_selected(file);
      }, function() { }, {limit: 1});
    }
  },
  swap_streams: function() {
    var video = document.querySelector('#webcam_video');
    var current_stream_id = this.controller.get('webcam.stream_id');
    var streams = this.controller.get('webcam.video_streams');
    var index = 0;
    for(var idx = 0; idx < streams.length; idx++) {
      if(current_stream_id && streams[idx].id == current_stream_id) {
        index = idx;
      }
    }
    var _this = this;
    if(streams && streams.length > 1) {
      index++;
      if(index > streams.length - 1) {
        index = 0;
      }
      var stream_id = streams[index] && streams[index].id;
      if(stream_id) {
        var stream = _this.controller.get('webcam.stream');
        if(stream && stream.stop) {
          stream.stop();
        } else if(stream && stream.getVideoTracks) {
          stream.getVideoTracks().forEach(function(track) {
            track.stop();
          });
        }
        if(video) { video.src = null; }
        navigator.getUserMedia({
          video: {
            optional: [{
              sourceId: stream_id
            }]
          }
        }, function(stream) {
          _this.user_media_ready(stream, stream_id);
        }, function() {
          console.log("permission not granted");
        });
      }
    }
  },
  toggle_webcam: function() {
    // TODO: needs a real home and non-suck
    // TODO: cross-browser - https://developer.mozilla.org/en-US/docs/WebRTC/taking_webcam_photos
    var video = document.querySelector('#webcam_video');
    var canvas = document.querySelector('#webcam_canvas');
    var ctx = canvas && canvas.getContext('2d');
    if(!ctx || this.controller.get('webcam.snapshot')) {
      this.controller.set('image_preview', null);
      this.controller.set('webcam.snapshot', false);
    } else if(this.controller.get('webcam.stream')) {
      ctx.drawImage(video, 0, 100, 800, 600);
      var data = canvas.toDataURL('image/png');
      this.controller.set('image_preview', {
        url: data
      });
      this.controller.set('webcam.snapshot', true);
      this.controller.set('image_preview.editor', null);
    }
  }
}).create();

var soundGrabber = Ember.Object.extend({
  setup: function(button, controller) {
    this.controller = controller;
    this.button = button;
    var _this = this;
    Ember.run.later(function() {
      button.findContentLocally().then(function() {
        var sound = button.get('sound');
        if(sound) {
          sound.check_for_editable_license();
        }
      });
    });
    _this.controller.addObserver('sound_preview', _this, _this.default_sound_preview_license);
  },
  clear: function() {
    var stream = this.controller.get('sound_recording.stream');
    if(stream && stream.stop) {
      stream.stop();
    } else if(stream && stream.getAudioTracks) {
      stream.getAudioTracks().forEach(function(track) {
        track.stop();
      });
    }
    this.toggle_recording_sound('stop');
  },
  clear_sound_work: function() {
    this.controller.set('sound_preview', null);
    this.clear();
    this.controller.set('sound_recording', null);
    Ember.$('#sound_upload').val('');
  },
  default_sound_preview_license: function() {
    var user = app_state.get('currentUser');
    if(user && this.controller.get('sound_preview')) {
      if(!this.controller.get('sound_preview.license')) {
       this.controller.set('sound_preview.license', {type: 'private'});
      }
      if(!this.controller.get('sound_preview.license.author_name') && this.controller.get('sound_preview.license')) {
        this.controller.set('sound_preview.license.author_name', user.get('user_name'));
      }
      if(!this.controller.get('sound_preview.license.author_url') && this.controller.get('sound_preview.license')) {
        this.controller.set('sound_preview.license.author_url', user.get('profile_url'));
      }
    }
  },
  file_selected: function(file) {
    var _this = this;
    var reader = contentGrabbers.read_file(file);
    reader.then(function(data) {
      _this.controller.set('sound_preview', {
        url: data.target.result,
        name: file.name
      });
    });
  },
  recorder_available: function() {
    return !!(navigator.getUserMedia || (navigator.device && navigator.device.capture && navigator.device.capture.captureAudio));
  },
  record_sound: function() {
    var _this = this;
    this.controller.set('sound_recording', {
      stream: this.controller.get('sound_recording.stream'),
      ready: true
    });
    this.controller.set('sound_preview', null);

    function stream_ready(stream) {
      _this.controller.set('sound_recording.stream', stream);
      var mr = new window.MediaRecorder(stream);
      _this.controller.set('sound_recording.media_recorder', mr);
      mr.addEventListener('dataavailable', function(event) {
        if(!_this.controller.get('sound_recording.blob') && _this.controller.get('sound_recording')) {
          _this.controller.set('sound_recording.blob', event.data);
        }
        _this.toggle_recording_sound('stop');
      });
      mr.addEventListener('recordingdone', function() {
        var blob = _this.controller.get('sound_recording.blob');
        var reader = contentGrabbers.read_file(blob);
        reader.then(function(data) {
          _this.controller.set('sound_preview', {
            from_recording: true,
            url: data.target.result,
            name: i18n.t('recorded_sound', "Recorded sound")
          });
          if(_this.controller.get('sound_recording')) {
            _this.controller.set('sound_recording.ready', false);
          }
        });
      });

      return mr;
    }

    if(navigator.getUserMedia) {
      if(this.controller.get('sound_recording.stream')) {
        stream_ready(this.controller.get('sound_recording.stream'));
        return;
      }
      navigator.getUserMedia({audio: true}, function(stream) {
        var mr = stream_ready(stream);

        if(stream && stream.id) {
          var context = new window.AudioContext();
          var source = context.createMediaStreamSource(stream);
          var analyser = context.createAnalyser();
          var ctx = Ember.$('#sound_levels')[0].getContext('2d');
          analyser.smoothingTimeConstant = 0.3;
          analyser.fftSize = 1024;
          var js = context.createScriptProcessor(2048, 1, 1);
          js.onaudioprocess = function() {
            // get the average, bincount is fftsize / 2
            var array =  new Uint8Array(analyser.frequencyBinCount);
            analyser.getByteFrequencyData(array);
            var values = 0;
            var average;

            var length = array.length;

            // get all the frequency amplitudes
            for (var i = 0; i < length; i++) {
                values += array[i];
            }

            var average = values / length;
            var pct = average / 130;

            var gradient = ctx.createLinearGradient(0,50,0,250);
            gradient.addColorStop(1,'#00ff00');
            gradient.addColorStop(0.25,'#ffff00');
            gradient.addColorStop(0,'#ff0000');
            // clear the current state
            ctx.clearRect(0, 0, 400, 300);

            // set the fill style
            ctx.fillStyle=gradient;

            // create the meters
            ctx.fillRect(100,275,200,-250*pct);
          };
  //        source.connect(analyser);
  //        analyser.connect(js);
  //        js.connect(context.destination);
        }
      }, function() {
        console.log("permission not granted");
      });
    } else if(navigator.device && navigator.device.capture && navigator.device.capture.captureAudio) {
      navigator.device.capture.captureAudio(function(files) {
        var media_file = files[0];
        var file = new window.File(media_file.name, media_file.localURL, media_file.type, media_file.lastModifiedDate, media_file.size);
        _this.file_selected(file);
      }, function() { }, {limit: 1});
    }
  },
  toggle_recording_sound: function(action) {
    if(!action) {
      action = this.controller.get('sound_recording.recording') ? 'stop' : 'start';
    }
    var mr = this.controller.get('sound_recording.media_recorder');
    if(action == 'start' && mr && mr.state == 'inactive') {
      this.controller.set('sound_recording.blob', null);
      this.controller.set('sound_recording.recording', true);
      mr.start(10000);
    } else if(action == 'stop' && mr && mr.state == 'recording') {
      this.controller.set('sound_recording.recording', false);
      mr.stop();
    }
  },
  select_sound_preview: function() {
    var preview = this.controller && this.controller.get('sound_preview');
    if(!preview || !preview.url) { return; }
    var _this = this;

    this.controller.set('model.pending_sound', true);
    if(preview.url.match(/^data:/)) {
      preview.content_type = preview.content_type || preview.url.split(/;/)[0].split(/:/)[1];
    }
    if(!preview.license || !preview.license.copyright_notice_url) {
      preview.license = preview.license || {};
      var license_url = null;
      var licenses = CoughDrop.licenseOptions;
      for(var idx = 0; idx < licenses.length; idx++) {
        if(licenses[idx].id == preview.license.type) {
          license_url = licenses[idx].url;
        }
      }
      preview.license.copyright_notice_url = license_url;
    }

    var sound_load = new Ember.RSVP.Promise(function(resolve, reject) {
      var a = new window.Audio();
      a.ondurationchange = function() {
        resolve({
          duration: a.duration
        });
      };
      a.onerror = function() {
        reject({error: "sound calculation failed"});
      };
      a.src = preview.url;
    });

    var save_sound = sound_load.then(function(data) {
      var sound = CoughDrop.store.createRecord('sound', {
        content_type: preview.content_type || '',
        url: preview.url,
        duration: data.duration,
        license: preview.license
      });

      return contentGrabbers.save_record(sound);
    });

    save_sound.then(function(sound) {
      var button_sound = {url: sound.get('url'), id: sound.id};
      _this.controller.set('model.sound', sound);
      _this.clear_sound_work();
      editManager.change_button(_this.controller.get('model.id'), {
        'sound': sound,
        'sound_id': sound.id
      });
      _this.controller.set('model.pending_sound', false);
    }, function(err) {
      err = err || {};
      err.error = err.error || "unexpected error";
      coughDropExtras.track_error("upload failed: " + err.error);
      alert(i18n.t('upload_failed', "upload failed: " + err.error));
      _this.controller.set('model.pending_sound', false);
    });
  },
  save_pending: function() {
    var _this = this;
    if(this.controller.get('sound_preview')) {
      this.select_sound_preview();
    } else if(this.controller.get('model.sound')) {
      var license = this.controller.get('model.sound.license');
      var original = this.controller.get('original_sound_license') || {};
      if(license.type != original.type || license.author_name != original.author_name || license.author_url != original.author_url) {
        this.controller.set('model.pending_sound', true);
        this.controller.get('model.sound').save().then(function() {
          _this.controller.set('model.pending_sound', false);
        }, function() {
          alert(i18n.t('save_failed', "Saving settings failed!"));
          _this.controller.set('model.pending_sound', false);
        });
      }
    }
  },
}).create();

var boardGrabber = Ember.Object.extend({
  setup: function(button, controller) {
    this.controller = controller;
    this.button = button;
  },
  clear: function() {
    this.controller.set('foundBoards', null);
    this.controller.set('linkedBoardName', null);
    this.controller.set('pending_board', null);
  },
  find_board: function() {
    var _this = this;
    var search_type = this.controller.get('board_search_type');
    this.controller.set('foundBoards', {term: this.controller.get('linkedBoardName'), ready: false});
    var find_args =  {};
    var q = this.controller.get('linkedBoardName');
    if(search_type == 'personal') {
      find_args = {user_id: 'self', include_shared: true};
    } else if(search_type == 'personal_public') {
      find_args = {user_id: 'self', public: true, include_shared: true};
    } else if(search_type == 'current_user') {
      find_args = {user_id: this.controller.get('board.user_name'), include_shared: true };
    } else if(search_type == 'current_user_starred') {
      find_args = {user_id: this.controller.get('board.user_name'), starred: true };
    } else if(search_type == 'personal_starred') {
      find_args = {user_id: 'self', starred: true};
    } else if(search_type == 'personal_public_starred') {
      find_args = {user_id: 'self', starred: true, public: true };
    } else {
      find_args = {public: true};
    }
    var url_prefix = new RegExp("^" + location.protocol + "//" + location.host + "/");
    var key = (this.controller.get('linkedBoardName') || "").replace(url_prefix, "");
    var keyed_find = Ember.RSVP.resolve([]);
    if(key.match(/^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+|\d+_\d+$/) || key) {
      // right now this is always doing a double-lookup, first for an exact
      // match by key and then by query string. It'd be better if it were only
      // one lookup..
      var keyed_find_args = Ember.$.extend({}, find_args, {key: key});
      keyed_find = CoughDrop.store.query('board', keyed_find_args);
    }
    keyed_find.then(function(data) {
      var board = data.find(function() { return true; });
      if(!board || !_this.controller.get('linkedBoardName')) {
        find_args.q = q;
        CoughDrop.store.query('board', find_args).then(function(data) {
          _this.controller.set('foundBoards.ready', true);
          _this.controller.set('foundBoards.results', data);
        });
      } else {
        _this.pick_board(board);
      }
    }, function() { });
  },
  build_board: function() {
    var board = CoughDrop.store.createRecord('board', {
      name: this.controller.get('linkedBoardName'),
      copy_access: true,
      grid: {}
    });
    var original_board = this.controller.get('board');
    if(original_board) {
      board.set('grid.rows', original_board.get('grid.rows') || 2);
      board.set('grid.columns', original_board.get('grid.columns') || 4);
    } else {
      board.set('grid.rows', 2);
      board.set('grid.columns', 4);
    }
    board.set('for_user_id', 'self');
    if(this.controller.get('supervisees')) {
      var sups = this.controller.get('supervisees');
      if(sups.length > 0) {
        var user_name = original_board.get('user_name');
        sups.forEach(function(sup) {
          if(sup.name == user_name) {
            board.set('for_user_id', sup.id);
          }
        });
      }
    }
    this.controller.set('pending_board', board);
  },
  cancel_build_board: function() {
    this.controller.set('pending_board', null);
  },
  create_board: function() {
    var board = this.controller.get('pending_board');
    if(board.get('copy_access')) {
      var original_board = this.controller.get('board');
      if(original_board) {
        board.set('license', original_board.get('license'));
        board.set('public', original_board.get('public'));
      }
    }
    var _this = this;
    board.save().then(function(board) {
      _this.pick_board(board);
    }, function() { });
  },
  pick_board: function(board) {
    editManager.change_button(this.controller.get('model.id'), {
      load_board: {
        id: board.id,
        key: board.get('key')
      }
    });
    this.clear();
  },
  files_dropped: function(files) {
    var board = null;
    for(var idx = 0; idx < files.length; idx++) {
      if(!board && files[idx].name.match(/\.(obf|obz)$/)) {
        board = files[idx];
      }
    }
    if(board) {
      boardGrabber.file_selected(board);
    } else {
      alert(i18n.t('no_board_found', "No valid board file found"));
    }
  },
  file_selected: function(board) {
    var data_uri = null;

    if(!board) {
      modal.close();
      modal.error(i18n.t('invalid_board_file', "Please select a valid board file (.obf or .obz)"));
      return;
    }
    var generate_data_uri = contentGrabbers.read_file(board);

    var progressor = Ember.Object.create();
    var error = modal.error;

    modal.open('importing-boards', progressor);

    var type = 'obf';
    if(board.name && board.name.match(/\.obz$/)) {
      type = 'obz';
    }

    var prep = generate_data_uri.then(function(data) {
      data_uri = data.target.result;
      return persistence.ajax('/api/v1/boards/imports', {
        type: 'POST',
        data: {
          type: type
        }
      });
    });

    var upload = prep.then(function(meta) {
      meta.remote_upload.data_url = data_uri;
      meta.remote_upload.success_method = 'POST';
      return contentGrabbers.upload_to_remote(meta.remote_upload);
    });

    var progress = upload.then(function(data) {
      if(data.progress) {
        return new Ember.RSVP.Promise(function(resolve, reject) {
          progress_tracker.track(data.progress, function(event) {
            if(event.status == 'errored') {
              progressor.set('errored', true);
              reject({error: 'processing failed'});
            } else if(event.status == 'finished') {
              progressor.set('finished', true);
              resolve(event.result);
            }
          });
        });
      } else {
        return Ember.RSVP.reject({error: 'not confirmed'});
      }
    });

    progress.then(function(boards) {
      if(boards[0] && boards[0].key) {
        if(modal.is_open('importing-boards')) {
          boardGrabber.transitioner.transitionTo('board', boards[0].key);
        } else {
          modal.notice(i18n.t('boards_imported', "Board(s) successfully imported!"));
        }
      } else {
        if(modal.is_open('importing-boards')) {
          modal.close();
        }
        modal.error(i18n.t('upload_failed', "Upload failed"));
      }
    }, function() {
      if(modal.is_open('importing-boards')) {
        modal.close();
      }
      error(i18n.t('upload_failed', "Upload failed"));
    });
  }
}).create();

var linkGrabber = Ember.Object.extend({
  setup: function(button, controller) {
    this.controller = controller;
    this.button = button;
  },
  clear: function() {
  },
  find_apps: function() {
    var _this = this;
    var os = this.controller.get('app_find_mode') || 'ios';
    var q = this.controller.get(os + '_app_name');
    this.controller.set('foundApps', {term: q, ready: false});
    if(os == 'ios' || os == 'android') {
      var lookup = persistence.ajax('/api/v1/search/apps?q=' + encodeURIComponent(q) + '&os=' + os, {
        type: 'GET'
      });

      return lookup.then(function(results) {
        _this.controller.set('foundApps.ready', true);
        _this.controller.set('foundApps.results', results);
      }, function() {
        _this.controller.set('foundApps.ready', true);
        _this.controller.set('foundApps.results', []);
      });
    } else {
      return Ember.RSVP.resolve([]);
    }
  },
  pick_app: function(app) {
    var os = this.controller.get('app_find_mode') || 'ios';
    if(!this.controller.get('model.apps')) {
      this.controller.set('model.apps', {web: {}});
    }
    this.controller.set('model.apps.' + os, app);
    this.controller.set('foundApps', null);
    console.log(this.controller.get('model.apps'));
  },
  set_custom: function() {
    var os = this.controller.get('app_find_mode') || 'ios';
    if(this.controller.get('model.apps.' + os)) {
      this.controller.set('model.apps.' + os + '.custom', true);
    }
  },
  set_app_find_mode: function(mode) {
    this.controller.set('app_find_mode', mode);
    if(!this.controller.get('model.apps')) {
      this.controller.set('model.apps', {web: {}});
    }
    this.controller.set('foundApps', null);
  }
}).create();

Ember.$(document).on('change', '#image_upload,#sound_upload,#board_upload,#avatar_upload', function(event) {
  var type = 'image';
  if(event.target.id == 'sound_upload') { type = 'sound'; }
  if(event.target.id == 'board_upload') { type = 'board'; }
  if(event.target.id == 'avatar_upload') { type = 'avatar'; }
  var files = event.target.files;
  contentGrabbers.file_selected(type, files);
}).on('drop', '.button_container', function(event) {
  event.preventDefault();
  event.stopPropagation();
  Ember.$('.button_container.drop_target').removeClass('drop_target');
  var id = Ember.$(this).find('.button').attr('data-id');
  contentGrabbers.content_dropped(id, event.dataTransfer);
}).on('drop', '.board_drop', function(event) {
  event.preventDefault();
  event.stopPropagation();
  boardGrabber.files_dropped(event.dataTransfer.files);
});

contentGrabbers.boardGrabber = boardGrabber;
contentGrabbers.soundGrabber = soundGrabber;
contentGrabbers.linkGrabber = linkGrabber;
contentGrabbers.pictureGrabber = pictureGrabber;
window.cg = contentGrabbers;
export default contentGrabbers;
