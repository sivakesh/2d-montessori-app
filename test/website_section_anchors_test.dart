// Section anchors and internal navigation: the anchor data model (automatic
// ids, uniqueness, stability, duplicates, sections saved before anchors),
// link validation (`#enquire`, `/teacher-training#enquire`), routes with a
// section, and the editor's link integrity checks (missing pages and
// sections, hidden sections, links broken elsewhere).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_anchors.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/content/website_link_targets.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';

Map<String, dynamic> _sectionMap(String id, {String name = '', String? anchor, String heading = '', bool hidden = false, List<Map<String, dynamic>> blocks = const []}) => {
      'id': id,
      'type': 'section',
      'v': 1,
      'name': {'en': name, 'ta': ''},
      'anchor': ?anchor,
      if (heading.isNotEmpty) 'heading': {'en': heading, 'ta': ''},
      if (hidden) 'hidden': true,
      'layout': '1',
      'columns': [
        {'id': 'c_$id', 'blocks': blocks},
      ],
    };

Map<String, dynamic> _buttons(String id, List<String> targets) => {
      'id': id,
      'type': 'buttons',
      'v': 1,
      'align': 'start',
      'buttons': [
        for (final (i, t) in targets.indexed) {'id': 'i_${id}_$i', 'label': {'en': 'Go $i', 'ta': ''}, 'target': t, 'variant': 'primary'},
      ],
    };

List<WebsiteBlock> _page(List<Map<String, dynamic>> raw) => BlockRegistry.parseList(raw);

StructuredBlock _s(List<WebsiteBlock> blocks, String id) => blocks.firstWhere((b) => b.id == id) as StructuredBlock;

Object? _plain(Object? v) => jsonDecode(jsonEncode(v, toEncodable: (o) => o.toString()));

void main() {
  group('anchor ids', () {
    test('slugs: readable, lowercase, URL-safe, never empty', () {
      expect(SectionAnchors.slugify('Enquire'), 'enquire');
      expect(SectionAnchors.slugify('Our Programs & Courses'), 'our-programs-courses');
      expect(SectionAnchors.slugify('  Teacher   Training!! '), 'teacher-training');
      expect(SectionAnchors.slugify('தமிழ்'), '', reason: 'no letter a–z or digit');
      expect(SectionAnchors.slugify('x' * 80).length, lessThanOrEqualTo(56));
      final blocks = _page([_sectionMap('b_s1', name: 'தமிழ்'), _sectionMap('b_s2'), _sectionMap('b_s3', heading: 'Fees & Dates')]);
      expect(SectionAnchors.effective(blocks), {'b_s1': 'section', 'b_s2': 'section-2', 'b_s3': 'fees-dates'}, reason: 'the name, else the heading, else “section”');
      for (final ok in ['enquire', 'our-programs', 'a1', 'x' * 64]) {
        expect(SectionAnchors.isValid(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'Enquire', 'two words', '-lead', 'trail-', 'double--hyphen', 'x' * 65, 'a_b', 'a#b']) {
        expect(SectionAnchors.isValid(bad), isFalse, reason: bad);
      }
    });

    test('duplicate names get unique ids in page order; stored anchors are claimed first', () {
      final blocks = _page([
        _sectionMap('b_s1', name: 'Enquire'),
        _sectionMap('b_s2', name: 'Enquire'),
        _sectionMap('b_s3', name: 'Programs', anchor: 'enquire-2'),
      ]);
      expect(SectionAnchors.effective(blocks), {'b_s3': 'enquire-2', 'b_s1': 'enquire', 'b_s2': 'enquire-3'});
    });

    test('a new section (added or inserted) is given a unique anchor from its name', () {
      final before = _page([_sectionMap('b_s1', name: 'Enquire', anchor: 'enquire')]);
      final created = BlockRegistry.create(BlockRegistry.section).withValue('name', const LocalizedText(en: 'Enquire'));
      final after = SectionAnchors.ensure([...before, created], previous: before);
      expect(SectionAnchors.stored(_s(after, created.id)), 'enquire-2');
      expect(SectionAnchors.stored(_s(after, 'b_s1')), 'enquire', reason: 'never changed');
      // One inserted with an anchor no other section uses keeps it.
      final template = _page([_sectionMap('b_tpl', name: 'Visit', anchor: 'visit-us')]).single;
      expect(SectionAnchors.stored(_s(SectionAnchors.ensure([...before, template], previous: before), 'b_tpl')), 'visit-us');
      // One inserted with an anchor already used here gets a new one.
      final clash = _page([_sectionMap('b_tpl2', name: 'Enquire again', anchor: 'enquire')]).single;
      expect(SectionAnchors.stored(_s(SectionAnchors.ensure([...before, clash], previous: before), 'b_tpl2')), 'enquire-again');
    });

    test('stable when renamed, reordered, edited, saved and reopened', () {
      final page = _page([_sectionMap('b_s1', name: 'Enquire', anchor: 'enquire'), _sectionMap('b_s2', name: 'Fees', anchor: 'fees')]);
      final renamed = SectionAnchors.ensure([_s(page, 'b_s1').withValue('name', _s(page, 'b_s2').text('name')), page[1]], previous: page);
      expect(SectionAnchors.stored(_s(renamed, 'b_s1')), 'enquire', reason: 'the name is the editor’s; the anchor stays');
      final reordered = SectionAnchors.ensure([page[1], page[0]], previous: page);
      expect(identical(reordered[0], page[1]), isTrue, reason: 'nothing to store');
      final reopened = BlockRegistry.parseList(_plain(BlockRegistry.toMapList(renamed)));
      expect(SectionAnchors.effective(reopened), {'b_s1': 'enquire', 'b_s2': 'fees'});
    });

    test('duplicating a section never duplicates its anchor', () {
      final page = _page([_sectionMap('b_s1', name: 'Enquire', anchor: 'enquire')]);
      final copy = BlockRegistry.duplicate(page.single) as StructuredBlock;
      expect(SectionAnchors.stored(copy), '', reason: 'cleared on the copy');
      final after = SectionAnchors.ensure([page.single, copy], previous: page);
      expect(SectionAnchors.stored(_s(after, copy.id)), 'enquire-2');
      expect(SectionAnchors.stored(_s(after, 'b_s1')), 'enquire');
    });

    test('duplicate and malformed stored anchors are reported, never changed silently', () {
      final page = _page([
        _sectionMap('b_s1', name: 'A', anchor: 'enquire'),
        _sectionMap('b_s2', name: 'B', anchor: 'enquire'),
        _sectionMap('b_s3', name: 'C', anchor: 'Not Valid'),
      ]);
      final errors = BlockRegistry.validate(page);
      expect(errors, contains(contains('Block 2 (Section): the anchor ID “enquire” is already used by block 1')));
      expect(errors, contains(contains('Block 3 (Section): the anchor ID “Not Valid” can use only lowercase letters')));
      expect(SectionAnchors.effective(page), {'b_s1': 'enquire'}, reason: 'visitors get one section per anchor; a malformed one none');
      final again = SectionAnchors.ensure(page, previous: page);
      expect(identical(again, page), isTrue);
    });

    test('sections saved before anchors: read the same way every time, saved back exactly as stored', () {
      final raw = [_sectionMap('b_s1', name: 'Enquire'), _sectionMap('b_s2', name: 'Enquire'), _buttons('b_btn', ['#enquire-2'])];
      final page = _page(raw);
      expect(_plain(BlockRegistry.toMapList(page)), _plain(raw), reason: 'no anchor key is added');
      expect(SectionAnchors.effective(page), {'b_s1': 'enquire', 'b_s2': 'enquire-2'});
      expect(SectionAnchors.effective(_page(raw)), SectionAnchors.effective(page), reason: 'deterministic');
      expect(BlockRegistry.validate(page), isEmpty);

      // Editing another block stores nothing.
      final edited = [page[0], page[1], (page[2] as StructuredBlock).withValue('align', 'center')];
      expect(SectionAnchors.ensure(edited, previous: page), same(edited));

      // Deleting the first “Enquire” would move the second's derived
      // anchor to “enquire”: it keeps “enquire-2”, now stored.
      final deleted = SectionAnchors.ensure([page[1], page[2]], previous: page);
      expect(SectionAnchors.stored(_s(deleted, 'b_s2')), 'enquire-2');
      expect(SectionAnchors.effective(deleted)['b_s2'], 'enquire-2');

      // Renaming one keeps the anchor it had.
      final renamed = SectionAnchors.ensure([_s(page, 'b_s1').withValue('name', _s(page, 'b_s1').text('name').withText('en', 'Contact us')), page[1], page[2]], previous: page);
      expect(SectionAnchors.stored(_s(renamed, 'b_s1')), 'enquire');
      expect(SectionAnchors.stored(_s(renamed, 'b_s2')), 'enquire-2', reason: '“enquire” was freed, which would have moved it: stored');
      expect(SectionAnchors.effective(renamed), {'b_s1': 'enquire', 'b_s2': 'enquire-2'});

      // Reordering same-named sections keeps each one's anchor.
      final reordered = SectionAnchors.ensure([page[1], page[0], page[2]], previous: page);
      expect(SectionAnchors.effective(reordered), {'b_s2': 'enquire-2', 'b_s1': 'enquire'});
    });

    test('publishing: a hidden same-named section above can’t move a visible section’s anchor', () {
      final page = _page([_sectionMap('b_s1', name: 'Enquire', hidden: true), _sectionMap('b_s2', name: 'Enquire')]);
      expect(SectionAnchors.effective(page)['b_s2'], 'enquire-2');
      expect(SectionAnchors.effective(BlockRegistry.withoutHidden(page))['b_s2'], 'enquire', reason: 'what visitors would get without the pin');
      final pinned = SectionAnchors.pinForVisitors(page, BlockRegistry.withoutHidden);
      expect(SectionAnchors.stored(_s(pinned, 'b_s2')), 'enquire-2');
      expect(SectionAnchors.effective(BlockRegistry.withoutHidden(pinned))['b_s2'], 'enquire-2', reason: 'visitors get the editor’s anchor');
      final plain = _page([_sectionMap('b_s1', name: 'Enquire'), _sectionMap('b_s2', name: 'Fees')]);
      expect(SectionAnchors.pinForVisitors(plain, BlockRegistry.withoutHidden), same(plain), reason: 'usually nothing is stored');
    });

    test('regenerate: from the name, unique among the other sections', () {
      final page = _page([_sectionMap('b_s1', name: 'Enquire', anchor: 'enquire'), _sectionMap('b_s2', name: 'Enquire', anchor: 'old')]);
      expect(SectionAnchors.regenerate(_s(page, 'b_s2'), page), 'enquire-2');
      expect(SectionAnchors.regenerate(_s(page, 'b_s1'), page), 'enquire', reason: 'its own anchor isn’t “taken”');
    });
  });

  group('link validation', () {
    test('section links are accepted; page and fragment are read separately', () {
      for (final ok in ['#enquire', '/teacher-training#enquire', '/admissions#enquire', '/#programs', '/pages/open-day#faq', '/admissions', '/pages/open-day', 'https://example.org/form#apply', 'mailto:office@example.org', 'tel:+911234567890']) {
        expect(SafeLinkTarget.validate(ok), isNull, reason: ok);
      }
      expect(SafeLinkTarget.split('/teacher-training#enquire'), (path: '/teacher-training', anchor: 'enquire'));
      expect(SafeLinkTarget.split('#enquire'), (path: '', anchor: 'enquire'));
      expect(SafeLinkTarget.split('/admissions'), (path: '/admissions', anchor: null));
      expect(SafeLinkTarget.isInternal('#enquire'), isTrue);
      expect(SafeLinkTarget.isInternal('https://example.org'), isFalse);
    });

    test('malformed and unsafe links are still refused, with useful messages', () {
      expect(SafeLinkTarget.validate('#'), contains('anchor ID'));
      expect(SafeLinkTarget.validate('#Enquire Now'), contains('not a section anchor ID'));
      expect(SafeLinkTarget.validate('/teacher-training#'), contains('anchor ID'));
      expect(SafeLinkTarget.validate('/unknown#enquire'), contains('Use a page of this website'));
      expect(SafeLinkTarget.validate('/app#enquire'), isNotNull, reason: 'a management route, even with a section');
      expect(SafeLinkTarget.validate('/admin_dashboard#x'), isNotNull);
      for (final bad in ['javascript:alert(1)', 'javascript:alert(1)#x', 'http://example.org#x', 'data:text/html,x', 'ftp://x', '#javascript:alert(1)', '/pages/Bad Slug#x']) {
        expect(SafeLinkTarget.validate(bad), isNotNull, reason: bad);
      }
    });

    test('links saved before still validate exactly as before', () {
      for (final ok in ['/', '/admissions', '/gallery', '/pages/open-day', '/pages/Open-Day', 'https://example.org/form', 'mailto:office@example.org', 'tel:+911234567890']) {
        expect(SafeLinkTarget.validate(ok), isNull, reason: ok);
      }
      for (final bad in ['', '/app', '/pages/Bad Slug', 'https://', 'http://example.org']) {
        expect(SafeLinkTarget.validate(bad), isNotNull, reason: bad);
      }
    });
  });

  group('routes with a section', () {
    test('path, anchor and the address a browser opens', () {
      expect(PublicRoutes.pathOf('/teacher-training#enquire'), '/teacher-training');
      expect(PublicRoutes.pathOf('#enquire'), '');
      expect(PublicRoutes.anchorOf('/teacher-training#enquire'), 'enquire');
      expect(PublicRoutes.anchorOf('/teacher-training'), isNull);
      expect(PublicRoutes.anchorOf('/#/app'), isNull, reason: 'a legacy hash route is not a section');
      expect(PublicRoutes.anchorOf('/x#Bad'), isNull);
      expect(PublicRoutes.sectionRoute('/teacher-training', '#enquire'), '/teacher-training#enquire');
      expect(PublicRoutes.sectionRoute('/', '#programs'), '/#programs');
      expect(PublicRoutes.sectionRoute('/', '#/pages/about'), isNull, reason: 'legacy hash URLs are routes');
      expect(PublicRoutes.sectionRoute('/admissions', ''), isNull);
      expect(PublicRoutes.sectionRoute('/admissions?x=1', '#enquire'), isNull);
      expect(PublicRoutes.legacyHashRoute('/', '#enquire'), isNull, reason: 'an ordinary anchor is not a route');
    });
  });

  group('link integrity', () {
    WebsiteLinkSite site({List<WebsiteBlock>? training, bool trainingPublished = true}) => WebsiteLinkSite(pages: [
          WebsiteLinkPage(route: '/', label: 'Home'),
          WebsiteLinkPage(
            route: '/teacher-training',
            label: 'Teacher Training',
            blocks: training ?? _page([_sectionMap('b_t1', name: 'Course'), _sectionMap('b_t2', name: 'Enquire', anchor: 'enquire'), _sectionMap('b_t3', name: 'Old', hidden: true)]),
            sectionsPublished: trainingPublished,
          ),
          WebsiteLinkPage(route: '/admissions', label: 'Admissions', blocks: _page([_sectionMap('b_a1', name: 'Enquire', anchor: 'enquire'), _buttons('b_a2', ['/teacher-training#enquire'])])),
          const WebsiteLinkPage(route: '/programs', label: 'Programs'),
          const WebsiteLinkPage(route: '/pages/open-day', label: 'Open Day', reachable: false),
          const WebsiteLinkPage(route: '/pages/old-day', label: 'Old Day', archived: true, reachable: false),
        ]);

    test('existing pages and sections are fine; missing ones are named', () {
      final s = site();
      expect(s.problemFor('/teacher-training#enquire', currentRoute: '/'), isNull);
      expect(s.problemFor('/admissions#enquire', currentRoute: '/'), isNull);
      expect(s.problemFor('#enquire', currentRoute: '/admissions'), isNull);
      expect(s.problemFor('/teacher-training', currentRoute: '/'), isNull);
      expect(s.problemFor('https://example.org', currentRoute: '/'), isNull, reason: 'external links aren’t checked against the site');
      expect(s.problemFor('/teacher-training#fees', currentRoute: '/'), contains('There is no section “#fees” on Teacher Training (/teacher-training)'));
      expect(s.problemFor('#fees', currentRoute: '/admissions'), contains('no section “#fees” on this page'));
      expect(s.problemFor('/pages/nowhere', currentRoute: '/'), 'There is no page at /pages/nowhere.');
      expect(s.problemFor('/pages/open-day#x', currentRoute: '/'), contains('isn’t published yet'));
      expect(s.problemFor('/pages/old-day', currentRoute: '/'), contains('archived'));
      expect(s.problemFor('/programs#x', currentRoute: '/'), contains('isn’t built with sections'));
      expect(s.problemFor('/teacher-training#old', currentRoute: '/'), contains('is hidden'));
      expect(site(trainingPublished: false).problemFor('/teacher-training#enquire', currentRoute: '/'), contains('isn’t published with its sections yet'));
      expect(s.problemFor('/Teacher-Training/#enquire', currentRoute: '/'), isNull, reason: 'pages matched as the app opens them');
    });

    test('a page’s links are listed with where they are', () {
      final blocks = _page([
        _sectionMap('b_s1', name: 'Intro', blocks: [_buttons('b_in', ['#gone', '/admissions'])]),
        _buttons('b_b', ['/teacher-training#nope', 'https://example.org']),
      ]);
      expect(site().withPage('/', blocks).linkProblems(blocks, currentRoute: '/'), [
        'Block 1 (Section), column 1, block 1 (Buttons), Button 1: There is no section “#gone” on this page. Choose one of its sections.',
        'Block 2 (Buttons), Button 1: There is no section “#nope” on Teacher Training (/teacher-training). Choose one of its sections.',
      ]);
    });

    test('deleting a section or changing its anchor shows the links it breaks elsewhere, and how many lead to it', () {
      final s = site();
      final training = s.pageFor('/teacher-training')!.blocks!;
      expect(s.brokenElsewhere('/teacher-training', training), isEmpty);
      final withoutEnquire = [for (final b in training) if (b.id != 'b_t2') b];
      expect(s.brokenElsewhere('/teacher-training', withoutEnquire), ['Admissions (/admissions), Block 2 (Buttons), Button 1: leads to “#enquire”, which isn’t on this page.']);
      final renamedAnchor = [for (final b in training) b.id == 'b_t2' ? (b as StructuredBlock).withValue('anchor', 'apply') : b];
      expect(s.brokenElsewhere('/teacher-training', renamedAnchor), hasLength(1));
      expect(s.linksTo('/teacher-training', 'enquire', training), 1, reason: 'the Admissions button');
      final here = [...training, ..._page([_buttons('b_here', ['#enquire', '/teacher-training#enquire'])])];
      expect(s.linksTo('/teacher-training', 'enquire', here), 3, reason: 'two on this page and one on Admissions');
      expect(s.withPage('/teacher-training', withoutEnquire).problemFor('/teacher-training#enquire', currentRoute: '/admissions'), isNotNull, reason: 'checked against the page as it is being edited');
    });
  });
}

