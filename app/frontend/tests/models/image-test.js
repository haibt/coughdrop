import DS from 'ember-data';
import Ember from 'ember';
import { test, moduleForModel } from 'ember-qunit';
import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { } from 'frontend/tests/helpers/ember_helper';
import CoughDrop from '../../app';

describe('Image', function() {
  describe("filename", function() {
    it("should not error on empty url", function() {
      var image = CoughDrop.store.createRecord('image', {});
      expect(image.get('filename')).toEqual('image');
    });
    it("should return filename if found in URL path, ignoring query params", function() {
      var image = CoughDrop.store.createRecord('image', {'url': 'http://www.yahoo.com/images/happy.png'});
      expect(image.get('filename')).toEqual('happy.png');
      image.set('url', 'http://www.google.com/images/radish.png?hat=12');
      expect(image.get('filename')).toEqual('radish.png');
      image.set('url', 'http://www.facebook.com/images/render.php?user_id=123112512');
      expect(image.get('filename')).toEqual('image');
      image.set('url', 'http://www.github.com/images/pic?user_id=123112512');
      expect(image.get('filename')).toEqual('image');
    });
    it("should return readable message for DATA URIs", function() {
      var image = CoughDrop.store.createRecord('image', {'url': 'data:image/png;abcabc'});
      expect(image.get('filename')).toEqual('embedded image');
    });
  });
  describe("license_string", function() {
    it("should not error on null value", function() {
      var image = CoughDrop.store.createRecord('image', {});
      expect(image.get('license_string')).toNotEqual(null);
    });
    it("should return human-readable value on null or empty", function() {
      var image = CoughDrop.store.createRecord('image', {});
      expect(image.get('license_string')).toEqual('Unknown. Assume all rights reserved');
      image.set('license', {});
      expect(image.get('license_string')).toEqual('Unknown. Assume all rights reserved');
    });
    it("should return appropriate string if provided", function() {
      var image = CoughDrop.store.createRecord('image', {license: {type: 'private'}});
      expect(image.get('license_string')).toEqual('All rights reserved');
      image.set('license', {type: 'CC By-SA'});
      expect(image.get('license_string')).toEqual('CC By-SA');
    });
  });
  describe("author_url_or_email", function() {
    it("should not error on empty string", function() {
      var image = CoughDrop.store.createRecord('image', {});
      expect(image.get('author_url_or_email')).toEqual(null);
      image.set('license', {});
      expect(image.get('author_url_or_email')).toEqual(null);
    });
    it("should return author_url if provided", function() {
      var image = CoughDrop.store.createRecord('image', {license: {author_url: "http://www.me.com"}});
      expect(image.get('author_url_or_email')).toEqual("http://www.me.com");
    });
    it("should return author_email if provided and no author_url", function() {
      var image = CoughDrop.store.createRecord('image', {license: {author_email: "me@example.com"}});
      expect(image.get('author_url_or_email')).toEqual("me@example.com");
      image.set('license.author_url', 'http://www.me.com');
      expect(image.get('author_url_or_email')).toEqual("http://www.me.com");
    });
  });
  it("should automatically check for locally-stored data-uri on load", function() {
    var image = CoughDrop.store.createRecord('image', {});
    image.didLoad();
    expect(image.get('checked_for_data_url')).toEqual(true);
  });
});
