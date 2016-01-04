import DS from 'ember-data';
import Ember from 'ember';
import { test, moduleForModel } from 'ember-qunit';
import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { db_wait, queue_promise } from 'frontend/tests/helpers/ember_helper';
import CoughDrop from '../../app';
import persistence from '../../utils/persistence';
import modal from '../../utils/modal';

describe('Buttonset', function() {
  describe("find_button", function() {
    it("should return an empty list for no search string", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {});
      expect(bs.find_buttons('')).toEqual([]);
      
      bs.set('buttons', [
        {'label': 'hat'}
      ]);
      expect(bs.find_buttons('')).toEqual([]);
    });
    
    it("should return matching buttons from the current board", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {'label': 'hat', 'depth': 0},
          {'label': 'box', 'depth': 0},
          {'label': 'nasty', 'depth': 0},
          {'label': 'nail', 'depth': 0}
        ]
      });
      queue_promise(bs.find_buttons('h')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('hat');
      });
      
      queue_promise(bs.find_buttons('hat')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('hat');
      });

      queue_promise(bs.find_buttons('hats')).then(function(res) {
        expect(res.length).toEqual(0);
      });

      queue_promise(bs.find_buttons('bo')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('box');
      });

      queue_promise(bs.find_buttons('na')).then(function(res) {
        expect(res.length).toEqual(2);
        expect(res[0].label).toEqual('nail');
        expect(res[1].label).toEqual('nasty');
      });
    });
    
    it("should return matching buttons from linked boards, including a path to access", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'hat', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'box', depth: 0},
          {label: 'can', depth: 1, board_id: '2', linked_board_id: '3'},
          {label: 'friend', depth: 2, board_id: '3', linked_board_id: '4'},
          {label: 'quarter', depth: 3, board_id: '4', linked_board_id: '5'},
          {label: 'olive', depth: 4, board_id: '5'}
        ]
      });
      
      queue_promise(bs.find_buttons('ca')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('can');
        expect(res[0].current_depth).toEqual(1);
        expect(res[0].pre_buttons).toNotEqual(null);
        expect(res[0].pre_buttons.length).toEqual(1);
        expect(res[0].pre_buttons[0].label).toEqual('hat');
      });
      
      queue_promise(bs.find_buttons('fri')).then(function(res) {
        expect(res.length).toEqual(1);
      });
      
      queue_promise(bs.find_buttons('ol')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('olive');
        expect(res[0].current_depth).toEqual(4);
        expect(res[0].pre_buttons.length).toEqual(4);
        expect(res[0].pre_buttons[0].label).toEqual('hat');
        expect(res[0].pre_buttons[1].label).toEqual('can');
        expect(res[0].pre_buttons[2].label).toEqual('friend');
        expect(res[0].pre_buttons[3].label).toEqual('quarter');
      });
    });
    
    it("should ignore hidden buttons by default", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'hat', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'have', depth: 0, hidden: true},
          {label: 'hair', depth: 1, board_id: '2', linked_board_id: '3'},
          {label: 'halt', depth: 2, board_id: '3', hidden: true}
        ]
      });
      
      queue_promise(bs.find_buttons('ha')).then(function(res) {
        expect(res.length).toEqual(2);
        expect(res[0].label).toEqual('hat');
        expect(res[1].label).toEqual('hair');
        expect(res[1].current_depth).toEqual(1);
        expect(res[1].pre_buttons).toNotEqual(null);
        expect(res[1].pre_buttons.length).toEqual(1);
        expect(res[1].pre_buttons[0].label).toEqual('hat');
      });
    });
    
    it("should not use paths created by link_disabled buttons", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'hat', depth: 0, board_id: '1', linked_board_id: '2', link_disabled: true},
          {label: 'have', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'hair', depth: 1, board_id: '2', linked_board_id: '3'}
        ]
      });
      
      queue_promise(bs.find_buttons('hair')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('hair');
        expect(res[0].current_depth).toEqual(1);
        expect(res[0].pre_buttons).toNotEqual(null);
        expect(res[0].pre_buttons.length).toEqual(1);
        expect(res[0].pre_buttons[0].label).toEqual('have');
      });
    });
    
    it("should default to preferred_link buttons", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'hat', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'have', depth: 0, board_id: '1', linked_board_id: '2', preferred_link: true},
          {label: 'hair', depth: 1, board_id: '2', linked_board_id: '3'}
        ]
      });
      
      queue_promise(bs.find_buttons('hair')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('hair');
        expect(res[0].current_depth).toEqual(1);
        expect(res[0].pre_buttons).toNotEqual(null);
        expect(res[0].pre_buttons.length).toEqual(1);
        expect(res[0].pre_buttons[0].label).toEqual('have');
      });
    });
    
    it("should use the shortest viable path", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'hat', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'box', depth: 0, board_id: '1', linked_board_id: '5'},
          {label: 'can', depth: 1, board_id: '2', linked_board_id: '3'},
          {label: 'friend', depth: 2, board_id: '3', linked_board_id: '4'},
          {label: 'quarter', depth: 3, board_id: '4', linked_board_id: '5'},
          {label: 'olive', depth: 4, board_id: '5'}
        ]
      });
      
      queue_promise(bs.find_buttons('oliv')).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('olive');
        expect(res[0].current_depth).toEqual(1);
        expect(res[0].pre_buttons.length).toEqual(1);
        expect(res[0].pre_buttons[0].label).toEqual('box');
      });
    });
    
    it("should not infinite loop on a matched button that can't be accessed from the current board", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'hat', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'box', depth: 0, board_id: '1', linked_board_id: '5'},
          {label: 'whatever', depth: 0, board_id: '1', linked_board_id: '7', hidden: true},
          {label: 'can', depth: 1, board_id: '2', linked_board_id: '3'},
          {label: 'friend', depth: 2, board_id: '3', linked_board_id: '4'},
          {label: 'quarter', depth: 3, board_id: '4', linked_board_id: '5', link_disabled: true},
          {label: 'olive', depth: 4, board_id: '5'},
          {label: 'pony', depth: 2, board_id: '6'},
          {label: 'truck', depth: 2, board_id: '7'}
        ]
      });
      
      queue_promise(bs.find_buttons('pon')).then(function(res) {
        expect(res.length).toEqual(0);
      });
      
      queue_promise(bs.find_buttons('truck')).then(function(res) {
        expect(res.length).toEqual(0);
      });
    });
    
    it("should not infinite loop on unexpected links", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'hat', depth: 0, board_id: '1'},
          {label: 'can', depth: 1, board_id: '2', linked_board_id: '3'},
          {label: 'friend', depth: 2, board_id: '3', linked_board_id: '2'}
        ]
      });
      
      queue_promise(bs.find_buttons('friend')).then(function(res) {
        expect(res.length).toEqual(0);
      });
      
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'a1', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'b2', depth: 1, board_id: '2', linked_board_id: '3'},
          {label: 'c3', depth: 2, board_id: '3', linked_board_id: '4'},
          {label: 'd4', depth: 3, board_id: '4', linked_board_id: '5'},
          {label: 'e5', depth: 4, board_id: '5', linked_board_id: '6'},
          {label: 'f6', depth: 5, board_id: '6', linked_board_id: '7'},
          {label: 'g7', depth: 6, board_id: '7', linked_board_id: '8'},
          {label: 'h8', depth: 7, board_id: '8', linked_board_id: '9'},
          {label: 'i9', depth: 8, board_id: '9', linked_board_id: '10'},
          {label: 'j10', depth: 9, board_id: '10', linked_board_id: '11'},
          {label: 'k11', depth: 10, board_id: '11', linked_board_id: '12'},
          {label: 'l12', depth: 11, board_id: '12', linked_board_id: '13'},
          {label: 'm13', depth: 12, board_id: '13', linked_board_id: '14'},
          {label: 'n14', depth: 13, board_id: '14', linked_board_id: '15'},
          {label: 'o15', depth: 14, board_id: '15', linked_board_id: '16'},
          {label: 'p16', depth: 15, board_id: '16', linked_board_id: '17'},
          {label: 'q17', depth: 16, board_id: '17', linked_board_id: '18'},
          {label: 'r18', depth: 17, board_id: '18', linked_board_id: '19'},
          {label: 's19', depth: 18, board_id: '19', linked_board_id: '20'},
          {label: 't20', depth: 19, board_id: '20'}
        ]
      });
      
      queue_promise(bs.find_buttons('m')).then(function(res) {
        expect(res.length).toEqual(1);
      });
      queue_promise(bs.find_buttons('n')).then(function(res) {
        expect(res.length).toEqual(1);
      });
      queue_promise(bs.find_buttons('o')).then(function(res) {
        expect(res.length).toEqual(1);
      });
      queue_promise(bs.find_buttons('p')).then(function(res) {
        expect(res.length).toEqual(1);
      });
      queue_promise(bs.find_buttons('q')).then(function(res) {
        expect(res.length).toEqual(0);
      });
      queue_promise(bs.find_buttons('r')).then(function(res) {
        expect(res.length).toEqual(0);
      });
      queue_promise(bs.find_buttons('s')).then(function(res) {
        expect(res.length).toEqual(0);
      });
      queue_promise(bs.find_buttons('t')).then(function(res) {
        expect(res.length).toEqual(0);
      });
    });
    
    it("should look up locally-cached images for use if available", function() {
      db_wait(function() {
        var stored = false;
        stub(persistence, 'ajax', function (options) {
          return Ember.RSVP.resolve({
            content_type: 'image/png',
            data: 'data:image/png;0'
          });
        });
        persistence.store_url('http://www.example.com').then(function() {
          stored = true;
        });
        
        var results = null;
        waitsFor(function() { return stored; });
        runs(function() {
          var bs = CoughDrop.store.createRecord('buttonset', {
            buttons: [
              {label: 'hat', depth: 0, board_id: '1', image: 'http://www.example.com'}
            ]
          });
          Ember.run.later(function() {
            bs.find_buttons('h').then(function(r) {
              results = r;
            });
          }, 100);
        });
        
        waitsFor(function() { return results; });
        runs(function() {
          expect(results.length).toEqual(1);
          expect(results[0].image).toEqual('data:image/png;0');
        });
      });
    });
    
    it("should optionally include buttons accessed via the home board if specified", function() {
      var user = CoughDrop.store.createRecord('user', {
        preferences: {
          home_board: {
            id: '123',
            key: 'abc/123'
          }
        }
      });
      var home_bs = CoughDrop.store.createRecord('buttonset', {
        id: '123',
        buttons: [
          {label: 'hat', depth: 0, board_id: '1'}
        ]
      });
      var home = CoughDrop.store.createRecord('board', {
        id: '123',
        key: 'abc/123'
      });
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: []
      });
      
      queue_promise(bs.find_buttons('hat', user, true)).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('hat');
        expect(res[0].pre_buttons.length).toEqual(1);
        expect(res[0].pre_buttons[0].board_id).toEqual('home');
      });
    });
    
    it("should not repeat buttons if they are accessible via the current board and the home board", function() {
      var user = CoughDrop.store.createRecord('user', {
        preferences: {
          home_board: {
            id: '123',
            key: 'abc/123'
          }
        }
      });
      var home_bs = CoughDrop.store.createRecord('buttonset', {
        id: '123',
        buttons: [
          {label: 'hat', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'cheese', depth: 1, id: '1', board_id: '2'}
        ]
      });
      var home = CoughDrop.store.createRecord('board', {
        id: '123',
        key: 'abc/123'
      });
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'cheese', depth: 0, id: '1', board_id: '2',}
        ]
      });
     
      queue_promise(bs.find_buttons('cheese', user, true)).then(function(res) {
        expect(res.length).toEqual(1);
        expect(res[0].label).toEqual('cheese');
        expect(res[0].pre_buttons).toEqual([]);
      });
    });
    
    it("should optionally include buttons accessed via the sidebar if specified", function() {
      var user = CoughDrop.store.createRecord('user', {
        preferences: {
          home_board: {
            id: '123',
            key: 'abc/123'
          },
          sidebar_boards: [
            {id: '234', key: '234'}
          ]
        }
      });
      var home_bs = CoughDrop.store.createRecord('buttonset', {
        id: '123',
        buttons: [
          {label: 'chop', depth: 0, id: '1', board_id: '3'}
        ]
      });
      var home = CoughDrop.store.createRecord('board', {
        id: '123',
        key: 'abc/123'
      });
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'cheese', depth: 0, id: '1', board_id: '2',}
        ]
      });
      var sidebar = CoughDrop.store.createRecord('board', {
        id: '234',
        key: '234'
      });
      var sidebar_bs = CoughDrop.store.createRecord('buttonset', {
        id: '234',
        buttons: [
          {label: 'chicken', depth: 0, id: '1', board_id: '1', linked_board_id: '4'},
          {label: 'charbroil', depth: 1, id: '1', board_id: '4'}
        ]
      });
     
      queue_promise(bs.find_buttons('ch', user, true)).then(function(res) {
        expect(res.length).toEqual(4);
        expect(res[0].label).toEqual('cheese');
        expect(res[0].pre_buttons.length).toEqual(0);
        expect(res[1].label).toEqual('charbroil');
        expect(res[1].pre_buttons.length).toEqual(2);
        expect(res[2].label).toEqual('chicken');
        expect(res[2].pre_buttons.length).toEqual(1);
        expect(res[3].label).toEqual('chop');
        expect(res[3].pre_buttons.length).toEqual(1);
      });
    });
    
    it("should order results first by on-current-board and then alphabetically", function() {
      var bs = CoughDrop.store.createRecord('buttonset', {
        buttons: [
          {label: 'alfalfa', depth: 0, board_id: '1', linked_board_id: '2'},
          {label: 'alabaster', depth: 0, board_id: '1', linked_board_id: '6'},
          {label: 'altruism', depth: 0, board_id: '1', linked_board_id: '7'},
          {label: 'axed', depth: 1, board_id: '2', linked_board_id: '3'},
          {label: 'aa', depth: 2, board_id: '3', linked_board_id: '4'},
          {label: 'android', depth: 3, board_id: '4', linked_board_id: '5'},
          {label: 'asking', depth: 4, board_id: '5'},
          {label: 'altimeter', depth: 2, board_id: '6'},
          {label: 'apatosaur', depth: 2, board_id: '7'}
        ]
      });
      
      queue_promise(bs.find_buttons('a')).then(function(res) {
        expect(res.length).toEqual(9);
        expect(res[0].label).toEqual('alabaster');
        expect(res[1].label).toEqual('alfalfa');
        expect(res[2].label).toEqual('altruism');
        expect(res[3].label).toEqual('aa');
        expect(res[4].label).toEqual('altimeter');
        expect(res[5].label).toEqual('android');
        expect(res[6].label).toEqual('apatosaur');
        expect(res[7].label).toEqual('asking');
        expect(res[8].label).toEqual('axed');
      });
    });
  });
});
