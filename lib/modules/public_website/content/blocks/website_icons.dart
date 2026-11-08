import 'package:flutter/material.dart';

/// One icon of the website's icon library: a stable stored [id] (pages
/// store only this, never drawn SVG or HTML), its name in the picker, its
/// category and extra search words.
@immutable
class WebsiteIcon {
  const WebsiteIcon(this.id, this.label, this.data, {required this.category, this.keywords = const []});

  final String id;
  final String label;
  final IconData data;
  final String category;
  final List<String> keywords;

  /// Whether [query] (lower case, trimmed) matches its name, id, category
  /// or search words.
  bool matches(String query) =>
      query.isEmpty ||
      label.toLowerCase().contains(query) ||
      id.replaceAll('_', ' ').contains(query) ||
      WebsiteIcons.categoryLabel(category).toLowerCase().contains(query) ||
      keywords.any((k) => k.contains(query));
}

/// The website's icon library, shared by the Icon block and Text blocks'
/// icons (and their picker). Material Symbols (outlined), which the app
/// already ships, so the look is consistent and nothing is downloaded;
/// web builds keep only the glyphs referenced here.
///
/// The ids of the Cards and Features blocks' icons ([blockIconNames]:
/// family, school, spa, …) are ids here too, with the same glyphs, so one
/// name means one icon everywhere.
///
/// An id this version doesn't know ([lookup] returns null: a newer app's
/// icon, or one removed) is kept as stored and drawn as nothing.
abstract final class WebsiteIcons {
  /// Picker categories, in order: id and name.
  static const categories = <(String, String)>[
    ('education', 'Education & Montessori'),
    ('people', 'People'),
    ('communication', 'Communication'),
    ('navigation', 'Navigation'),
    ('activities', 'Activities'),
    ('nature', 'Nature & care'),
    ('places', 'Facilities & places'),
    ('business', 'Business & time'),
    ('general', 'General'),
    ('media', 'Media & social'),
  ];

  static String categoryLabel(String id) {
    for (final (c, label) in categories) {
      if (c == id) return label;
    }
    return id;
  }

  /// A well-formed stored id: lower case letters, digits and underscores.
  static final _idPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
  static bool isWellFormed(String id) => _idPattern.hasMatch(id);

  static WebsiteIcon? lookup(String id) => _byId[id];

  static final Map<String, WebsiteIcon> _byId = {for (final i in all) i.id: i};

  /// The icons of [category] (null: all) matching [query].
  static List<WebsiteIcon> search(String query, {String? category}) {
    final q = query.trim().toLowerCase();
    return [for (final i in all) if ((category == null || i.category == category) && i.matches(q)) i];
  }

  static const _e = 'education', _p = 'people', _c = 'communication', _n = 'navigation', _a = 'activities';
  static const _nc = 'nature', _f = 'places', _b = 'business', _g = 'general', _m = 'media';

  static const all = <WebsiteIcon>[
    // Education & Montessori
    WebsiteIcon('book', 'Book', Icons.menu_book_outlined, category: _e, keywords: ['reading', 'open book']),
    WebsiteIcon('books', 'Books', Icons.library_books_outlined, category: _e, keywords: ['reading', 'curriculum']),
    WebsiteIcon('story_book', 'Story book', Icons.auto_stories_outlined, category: _e, keywords: ['reading', 'stories']),
    WebsiteIcon('school', 'Graduation cap', Icons.school_outlined, category: _e, keywords: ['school', 'graduate', 'education']),
    WebsiteIcon('pencil', 'Pencil', Icons.edit_outlined, category: _e, keywords: ['write', 'edit']),
    WebsiteIcon('draw', 'Drawing', Icons.draw_outlined, category: _e, keywords: ['pen', 'write', 'sketch']),
    WebsiteIcon('ruler', 'Ruler', Icons.straighten_outlined, category: _e, keywords: ['measure']),
    WebsiteIcon('backpack', 'Backpack', Icons.backpack_outlined, category: _e, keywords: ['school bag']),
    WebsiteIcon('alphabet', 'Alphabet', Icons.abc_outlined, category: _e, keywords: ['abc', 'letters', 'phonics']),
    WebsiteIcon('calculator', 'Calculator', Icons.calculate_outlined, category: _e, keywords: ['maths', 'math', 'numbers']),
    WebsiteIcon('numbers', 'Numbers', Icons.numbers_outlined, category: _e, keywords: ['maths', 'counting']),
    WebsiteIcon('globe', 'Globe', Icons.public_outlined, category: _e, keywords: ['world', 'geography', 'earth']),
    WebsiteIcon('science', 'Science', Icons.science_outlined, category: _e, keywords: ['experiment', 'flask']),
    WebsiteIcon('microscope', 'Microscope', Icons.biotech_outlined, category: _e, keywords: ['science', 'biology']),
    WebsiteIcon('quiz', 'Quiz', Icons.quiz_outlined, category: _e, keywords: ['question', 'test']),
    WebsiteIcon('class', 'Class', Icons.class_outlined, category: _e, keywords: ['lesson', 'notebook']),
    WebsiteIcon('history', 'History', Icons.history_edu_outlined, category: _e, keywords: ['scroll', 'writing']),
    WebsiteIcon('mind', 'Mind', Icons.psychology_outlined, category: _e, keywords: ['thinking', 'brain', 'learning']),
    WebsiteIcon('translate', 'Languages', Icons.translate_outlined, category: _e, keywords: ['translate', 'language', 'tamil']),
    WebsiteIcon('spelling', 'Spelling', Icons.spellcheck_outlined, category: _e, keywords: ['words', 'reading']),
    WebsiteIcon('grid', 'Materials', Icons.grid_view_outlined, category: _e, keywords: ['montessori', 'materials', 'blocks', 'grid']),
    WebsiteIcon('lightbulb', 'Idea', Icons.lightbulb_outline, category: _e, keywords: ['lightbulb', 'idea', 'discover']),

    // People
    WebsiteIcon('user', 'Person', Icons.person_outline, category: _p, keywords: ['user', 'profile']),
    WebsiteIcon('users', 'People', Icons.people_outline, category: _p, keywords: ['users', 'parents']),
    WebsiteIcon('group', 'Group', Icons.groups_outlined, category: _p, keywords: ['community', 'team']),
    WebsiteIcon('family', 'Family', Icons.family_restroom_outlined, category: _p, keywords: ['parents', 'children']),
    WebsiteIcon('child', 'Child', Icons.child_care_outlined, category: _p, keywords: ['children', 'baby', 'toddler']),
    WebsiteIcon('stroller', 'Stroller', Icons.child_friendly_outlined, category: _p, keywords: ['infant', 'baby', 'pram']),
    WebsiteIcon('boy', 'Boy', Icons.boy_outlined, category: _p, keywords: ['child', 'student']),
    WebsiteIcon('girl', 'Girl', Icons.girl_outlined, category: _p, keywords: ['child', 'student']),
    WebsiteIcon('teacher', 'Teacher', Icons.co_present_outlined, category: _p, keywords: ['presenter', 'educator', 'guide']),
    WebsiteIcon('face', 'Face', Icons.face_outlined, category: _p, keywords: ['smile', 'child']),
    WebsiteIcon('diversity', 'Diversity', Icons.diversity_3_outlined, category: _p, keywords: ['inclusion', 'community']),
    WebsiteIcon('handshake', 'Handshake', Icons.handshake_outlined, category: _p, keywords: ['partnership', 'welcome']),
    WebsiteIcon('accessibility', 'Accessibility', Icons.accessibility_new_outlined, category: _p, keywords: ['inclusive']),
    WebsiteIcon('staff', 'Staff badge', Icons.badge_outlined, category: _p, keywords: ['id', 'staff', 'employee']),
    WebsiteIcon('supervisor', 'Supervisor', Icons.supervisor_account_outlined, category: _p, keywords: ['admin', 'manager']),
    WebsiteIcon('add_person', 'Join', Icons.person_add_alt_outlined, category: _p, keywords: ['enrol', 'admission', 'register']),
    WebsiteIcon('elderly', 'Grandparent', Icons.elderly_outlined, category: _p, keywords: ['grandparents', 'elders']),
    WebsiteIcon('pregnant', 'Expecting parent', Icons.pregnant_woman_outlined, category: _p, keywords: ['mother', 'prenatal']),

    // Communication
    WebsiteIcon('phone', 'Phone', Icons.phone_outlined, category: _c, keywords: ['call', 'telephone']),
    WebsiteIcon('mail', 'Email', Icons.mail_outline, category: _c, keywords: ['mail', 'letter', 'envelope']),
    WebsiteIcon('message', 'Message', Icons.message_outlined, category: _c, keywords: ['text']),
    WebsiteIcon('chat', 'Chat', Icons.chat_bubble_outline, category: _c, keywords: ['talk', 'conversation']),
    WebsiteIcon('forum', 'Discussion', Icons.forum_outlined, category: _c, keywords: ['chat', 'conversation']),
    WebsiteIcon('sms', 'SMS', Icons.sms_outlined, category: _c, keywords: ['text message']),
    WebsiteIcon('bell', 'Bell', Icons.notifications_none_outlined, category: _c, keywords: ['notification', 'alert']),
    WebsiteIcon('notification', 'Notification', Icons.notifications_active_outlined, category: _c, keywords: ['bell', 'alert', 'reminder']),
    WebsiteIcon('announcement', 'Announcement', Icons.campaign_outlined, category: _c, keywords: ['megaphone', 'news']),
    WebsiteIcon('contact_card', 'Contact details', Icons.contact_mail_outlined, category: _c, keywords: ['address', 'contact']),
    WebsiteIcon('contact_phone', 'Contact number', Icons.contact_phone_outlined, category: _c, keywords: ['phone', 'contact']),
    WebsiteIcon('support', 'Support', Icons.support_agent_outlined, category: _c, keywords: ['help', 'helpdesk']),
    WebsiteIcon('feedback', 'Feedback', Icons.feedback_outlined, category: _c, keywords: ['comment', 'review']),
    WebsiteIcon('question', 'Question', Icons.help_outline, category: _c, keywords: ['help', 'faq']),
    WebsiteIcon('answers', 'Questions & answers', Icons.question_answer_outlined, category: _c, keywords: ['faq', 'chat']),
    WebsiteIcon('quote', 'Quote', Icons.format_quote_outlined, category: _c, keywords: ['testimonial', 'saying']),
    WebsiteIcon('info', 'Information', Icons.info_outline, category: _c, keywords: ['about', 'details']),
    WebsiteIcon('send', 'Send', Icons.send_outlined, category: _c, keywords: ['submit', 'paper plane']),
    WebsiteIcon('at', 'At sign', Icons.alternate_email, category: _c, keywords: ['email', 'handle']),

    // Navigation
    WebsiteIcon('home', 'Home', Icons.home_outlined, category: _n, keywords: ['house', 'start']),
    WebsiteIcon('menu', 'Menu', Icons.menu, category: _n, keywords: ['hamburger', 'list']),
    WebsiteIcon('arrow_right', 'Arrow right', Icons.arrow_forward, category: _n, keywords: ['next', 'forward']),
    WebsiteIcon('arrow_left', 'Arrow left', Icons.arrow_back, category: _n, keywords: ['back', 'previous']),
    WebsiteIcon('arrow_up', 'Arrow up', Icons.arrow_upward, category: _n, keywords: ['top']),
    WebsiteIcon('arrow_down', 'Arrow down', Icons.arrow_downward, category: _n, keywords: ['bottom']),
    WebsiteIcon('arrow_up_right', 'Arrow up right', Icons.north_east, category: _n, keywords: ['diagonal', 'go']),
    WebsiteIcon('chevron_right', 'Chevron right', Icons.chevron_right, category: _n, keywords: ['next']),
    WebsiteIcon('chevron_left', 'Chevron left', Icons.chevron_left, category: _n, keywords: ['previous']),
    WebsiteIcon('chevron_down', 'Chevron down', Icons.expand_more, category: _n, keywords: ['expand', 'more']),
    WebsiteIcon('external_link', 'External link', Icons.open_in_new, category: _n, keywords: ['new tab', 'open']),
    WebsiteIcon('search', 'Search', Icons.search, category: _n, keywords: ['find', 'magnifier']),
    WebsiteIcon('link', 'Link', Icons.link, category: _n, keywords: ['url', 'chain']),
    WebsiteIcon('refresh', 'Refresh', Icons.refresh, category: _n, keywords: ['reload']),
    WebsiteIcon('close', 'Close', Icons.close, category: _n, keywords: ['cross', 'x']),
    WebsiteIcon('more', 'More', Icons.more_horiz, category: _n, keywords: ['dots', 'ellipsis']),
    WebsiteIcon('apps', 'Apps', Icons.apps, category: _n, keywords: ['grid', 'menu']),
    WebsiteIcon('login', 'Sign in', Icons.login, category: _n, keywords: ['login', 'enter', 'portal']),

    // Activities
    WebsiteIcon('music', 'Music', Icons.music_note_outlined, category: _a, keywords: ['song', 'note']),
    WebsiteIcon('piano', 'Piano', Icons.piano_outlined, category: _a, keywords: ['music', 'keyboard']),
    WebsiteIcon('palette', 'Art', Icons.palette_outlined, category: _a, keywords: ['palette', 'paint', 'colour', 'color']),
    WebsiteIcon('brush', 'Paintbrush', Icons.brush_outlined, category: _a, keywords: ['paint', 'art']),
    WebsiteIcon('puzzle', 'Puzzle', Icons.extension_outlined, category: _a, keywords: ['piece', 'game']),
    WebsiteIcon('toys', 'Toys', Icons.toys_outlined, category: _a, keywords: ['play', 'windmill']),
    WebsiteIcon('shapes', 'Shapes', Icons.interests_outlined, category: _a, keywords: ['blocks', 'geometry', 'interests']),
    WebsiteIcon('football', 'Football', Icons.sports_soccer_outlined, category: _a, keywords: ['sport', 'soccer', 'ball']),
    WebsiteIcon('basketball', 'Basketball', Icons.sports_basketball_outlined, category: _a, keywords: ['sport', 'ball']),
    WebsiteIcon('swimming', 'Swimming', Icons.pool_outlined, category: _a, keywords: ['pool', 'sport']),
    WebsiteIcon('running', 'Running', Icons.directions_run_outlined, category: _a, keywords: ['sport', 'run', 'race']),
    WebsiteIcon('yoga', 'Yoga', Icons.self_improvement_outlined, category: _a, keywords: ['meditation', 'mindfulness', 'calm']),
    WebsiteIcon('drama', 'Drama', Icons.theater_comedy_outlined, category: _a, keywords: ['theatre', 'theater', 'masks']),
    WebsiteIcon('celebration', 'Celebration', Icons.celebration_outlined, category: _a, keywords: ['party', 'festival']),
    WebsiteIcon('cake', 'Birthday', Icons.cake_outlined, category: _a, keywords: ['cake', 'party']),
    WebsiteIcon('trophy', 'Trophy', Icons.emoji_events_outlined, category: _a, keywords: ['award', 'winner', 'prize']),
    WebsiteIcon('cooking', 'Cooking', Icons.soup_kitchen_outlined, category: _a, keywords: ['kitchen', 'food', 'practical life']),
    WebsiteIcon('meals', 'Meals', Icons.restaurant_outlined, category: _a, keywords: ['food', 'lunch', 'snack']),
    WebsiteIcon('gardening', 'Gardening', Icons.yard_outlined, category: _a, keywords: ['garden', 'plants']),

    // Nature & care
    WebsiteIcon('nature', 'Tree', Icons.park_outlined, category: _nc, keywords: ['park', 'outdoors', 'nature']),
    WebsiteIcon('spa', 'Calm', Icons.spa_outlined, category: _nc, keywords: ['spa', 'lotus', 'wellbeing']),
    WebsiteIcon('leaf', 'Leaf', Icons.eco_outlined, category: _nc, keywords: ['eco', 'green', 'environment']),
    WebsiteIcon('forest', 'Forest', Icons.forest_outlined, category: _nc, keywords: ['trees', 'outdoors']),
    WebsiteIcon('flower', 'Flower', Icons.local_florist_outlined, category: _nc, keywords: ['plant', 'garden']),
    WebsiteIcon('grass', 'Grass', Icons.grass_outlined, category: _nc, keywords: ['lawn', 'outdoors']),
    WebsiteIcon('sun', 'Sun', Icons.wb_sunny_outlined, category: _nc, keywords: ['sunny', 'weather', 'summer']),
    WebsiteIcon('cloud', 'Cloud', Icons.cloud_outlined, category: _nc, keywords: ['weather']),
    WebsiteIcon('water', 'Water', Icons.water_drop_outlined, category: _nc, keywords: ['drop', 'drink']),
    WebsiteIcon('pets', 'Pets', Icons.pets_outlined, category: _nc, keywords: ['animals', 'paw']),
    WebsiteIcon('bug', 'Insects', Icons.pest_control_outlined, category: _nc, keywords: ['bug', 'nature study']),
    WebsiteIcon('recycling', 'Recycling', Icons.recycling_outlined, category: _nc, keywords: ['eco', 'environment']),
    WebsiteIcon('heart', 'Heart', Icons.favorite_border, category: _nc, keywords: ['love', 'care']),
    WebsiteIcon('care', 'Caring hands', Icons.volunteer_activism_outlined, category: _nc, keywords: ['care', 'kindness', 'volunteer']),
    WebsiteIcon('health', 'Health & safety', Icons.health_and_safety_outlined, category: _nc, keywords: ['safety', 'wellbeing']),
    WebsiteIcon('medical', 'First aid', Icons.medical_services_outlined, category: _nc, keywords: ['medical', 'nurse', 'doctor']),
    WebsiteIcon('hygiene', 'Hygiene', Icons.clean_hands_outlined, category: _nc, keywords: ['clean', 'hands', 'washing']),
    WebsiteIcon('sanitizer', 'Sanitiser', Icons.sanitizer_outlined, category: _nc, keywords: ['clean', 'hygiene']),
    WebsiteIcon('nap', 'Nap time', Icons.bedtime_outlined, category: _nc, keywords: ['sleep', 'rest', 'moon']),

    // Facilities & places
    WebsiteIcon('building', 'Building', Icons.apartment_outlined, category: _f, keywords: ['school building', 'campus']),
    WebsiteIcon('office', 'Office', Icons.business_outlined, category: _f, keywords: ['building', 'admin']),
    WebsiteIcon('city', 'City', Icons.location_city_outlined, category: _f, keywords: ['town']),
    WebsiteIcon('classroom', 'Classroom', Icons.meeting_room_outlined, category: _f, keywords: ['room', 'door']),
    WebsiteIcon('library', 'Library', Icons.local_library_outlined, category: _f, keywords: ['reading', 'books']),
    WebsiteIcon('playground', 'Playground', Icons.attractions_outlined, category: _f, keywords: ['play', 'outdoors', 'rides']),
    WebsiteIcon('kitchen', 'Kitchen', Icons.kitchen_outlined, category: _f, keywords: ['fridge', 'food']),
    WebsiteIcon('bus', 'School bus', Icons.directions_bus_outlined, category: _f, keywords: ['transport', 'bus']),
    WebsiteIcon('car', 'Car', Icons.directions_car_outlined, category: _f, keywords: ['drop off', 'transport']),
    WebsiteIcon('bicycle', 'Bicycle', Icons.pedal_bike_outlined, category: _f, keywords: ['bike', 'cycle']),
    WebsiteIcon('walking', 'Walking', Icons.directions_walk_outlined, category: _f, keywords: ['walk', 'pedestrian']),
    WebsiteIcon('place', 'Location', Icons.place_outlined, category: _f, keywords: ['pin', 'address', 'location']),
    WebsiteIcon('map', 'Map', Icons.map_outlined, category: _f, keywords: ['directions', 'area']),
    WebsiteIcon('directions', 'Directions', Icons.directions_outlined, category: _f, keywords: ['route', 'sign']),
    WebsiteIcon('parking', 'Parking', Icons.local_parking_outlined, category: _f, keywords: ['car park']),
    WebsiteIcon('accessible', 'Wheelchair access', Icons.accessible_outlined, category: _f, keywords: ['accessible', 'disability']),
    WebsiteIcon('fence', 'Safe grounds', Icons.fence_outlined, category: _f, keywords: ['fence', 'enclosed', 'garden']),
    WebsiteIcon('store', 'Shop', Icons.storefront_outlined, category: _f, keywords: ['uniform', 'store']),
    WebsiteIcon('wifi', 'Wi-Fi', Icons.wifi, category: _f, keywords: ['internet', 'wireless']),
    WebsiteIcon('flag', 'Flag', Icons.flag_outlined, category: _f, keywords: ['milestone', 'goal']),

    // Business & time
    WebsiteIcon('calendar', 'Calendar', Icons.event_outlined, category: _b, keywords: ['event', 'date']),
    WebsiteIcon('calendar_month', 'Month', Icons.calendar_month_outlined, category: _b, keywords: ['calendar', 'schedule', 'term']),
    WebsiteIcon('event_ok', 'Event booked', Icons.event_available_outlined, category: _b, keywords: ['calendar', 'booked', 'confirmed']),
    WebsiteIcon('clock', 'Clock', Icons.schedule_outlined, category: _b, keywords: ['time', 'hours', 'timing']),
    WebsiteIcon('alarm', 'Alarm', Icons.alarm_outlined, category: _b, keywords: ['time', 'reminder']),
    WebsiteIcon('timer', 'Timer', Icons.timer_outlined, category: _b, keywords: ['stopwatch', 'duration']),
    WebsiteIcon('recent', 'Recent', Icons.history, category: _b, keywords: ['history', 'past']),
    WebsiteIcon('document', 'Document', Icons.description_outlined, category: _b, keywords: ['file', 'form', 'paper']),
    WebsiteIcon('article', 'Article', Icons.article_outlined, category: _b, keywords: ['news', 'blog', 'page']),
    WebsiteIcon('clipboard', 'Clipboard', Icons.content_paste_outlined, category: _b, keywords: ['paste', 'notes']),
    WebsiteIcon('assignment', 'Assignment', Icons.assignment_outlined, category: _b, keywords: ['homework', 'clipboard', 'task']),
    WebsiteIcon('checklist', 'Checklist', Icons.checklist_outlined, category: _b, keywords: ['list', 'tasks', 'todo']),
    WebsiteIcon('chart', 'Bar chart', Icons.bar_chart_outlined, category: _b, keywords: ['statistics', 'graph']),
    WebsiteIcon('pie_chart', 'Pie chart', Icons.pie_chart_outline, category: _b, keywords: ['statistics', 'graph']),
    WebsiteIcon('growth', 'Growth', Icons.trending_up, category: _b, keywords: ['progress', 'increase']),
    WebsiteIcon('wallet', 'Wallet', Icons.account_balance_wallet_outlined, category: _b, keywords: ['money', 'fees']),
    WebsiteIcon('payment', 'Payment', Icons.payments_outlined, category: _b, keywords: ['money', 'cash', 'fees']),
    WebsiteIcon('card', 'Card payment', Icons.credit_card_outlined, category: _b, keywords: ['credit card', 'debit']),
    WebsiteIcon('receipt', 'Receipt', Icons.receipt_long_outlined, category: _b, keywords: ['bill', 'invoice']),
    WebsiteIcon('rupee', 'Rupee', Icons.currency_rupee_outlined, category: _b, keywords: ['money', 'fees', 'inr']),
    WebsiteIcon('bank', 'Bank', Icons.account_balance_outlined, category: _b, keywords: ['finance']),
    WebsiteIcon('work', 'Careers', Icons.work_outline, category: _b, keywords: ['job', 'briefcase', 'vacancy']),
    WebsiteIcon('folder', 'Folder', Icons.folder_outlined, category: _b, keywords: ['files']),
    WebsiteIcon('print', 'Print', Icons.print_outlined, category: _b, keywords: ['printer']),
    WebsiteIcon('attachment', 'Attachment', Icons.attach_file, category: _b, keywords: ['paperclip', 'file']),

    // General
    WebsiteIcon('check', 'Check', Icons.check_circle_outline, category: _g, keywords: ['tick', 'done', 'yes']),
    WebsiteIcon('tick', 'Tick', Icons.done, category: _g, keywords: ['check', 'done']),
    WebsiteIcon('star', 'Star', Icons.star_outline, category: _g, keywords: ['favourite', 'rating']),
    WebsiteIcon('sparkle', 'Sparkle', Icons.auto_awesome_outlined, category: _g, keywords: ['magic', 'new', 'special']),
    WebsiteIcon('shield', 'Shield', Icons.shield_outlined, category: _g, keywords: ['safe', 'protection', 'security']),
    WebsiteIcon('verified', 'Verified', Icons.verified_outlined, category: _g, keywords: ['approved', 'certified', 'badge']),
    WebsiteIcon('medal', 'Medal', Icons.workspace_premium_outlined, category: _g, keywords: ['award', 'accreditation', 'quality']),
    WebsiteIcon('settings', 'Settings', Icons.settings_outlined, category: _g, keywords: ['gear', 'cog']),
    WebsiteIcon('thumb_up', 'Thumbs up', Icons.thumb_up_outlined, category: _g, keywords: ['like', 'good']),
    WebsiteIcon('smile', 'Smile', Icons.sentiment_satisfied_outlined, category: _g, keywords: ['happy', 'emoji']),
    WebsiteIcon('lock', 'Lock', Icons.lock_outline, category: _g, keywords: ['secure', 'private']),
    WebsiteIcon('key', 'Key', Icons.key_outlined, category: _g, keywords: ['access']),
    WebsiteIcon('warning', 'Warning', Icons.warning_amber_outlined, category: _g, keywords: ['alert', 'caution']),
    WebsiteIcon('plus', 'Plus', Icons.add, category: _g, keywords: ['add', 'new']),
    WebsiteIcon('bookmark', 'Bookmark', Icons.bookmark_border, category: _g, keywords: ['save']),
    WebsiteIcon('tag', 'Tag', Icons.local_offer_outlined, category: _g, keywords: ['label', 'offer', 'price']),
    WebsiteIcon('gift', 'Gift', Icons.card_giftcard_outlined, category: _g, keywords: ['present']),
    WebsiteIcon('diamond', 'Diamond', Icons.diamond_outlined, category: _g, keywords: ['premium', 'value']),
    WebsiteIcon('rocket', 'Rocket', Icons.rocket_launch_outlined, category: _g, keywords: ['launch', 'start']),
    WebsiteIcon('bolt', 'Lightning', Icons.bolt, category: _g, keywords: ['energy', 'fast']),
    WebsiteIcon('visible', 'Eye', Icons.visibility_outlined, category: _g, keywords: ['view', 'see', 'vision']),
    WebsiteIcon('target', 'Target', Icons.track_changes, category: _g, keywords: ['goal', 'aim', 'mission']),

    // Media & social
    WebsiteIcon('camera', 'Camera', Icons.photo_camera_outlined, category: _m, keywords: ['photo']),
    WebsiteIcon('image', 'Image', Icons.image_outlined, category: _m, keywords: ['picture', 'photo']),
    WebsiteIcon('photos', 'Photo gallery', Icons.photo_library_outlined, category: _m, keywords: ['gallery', 'album']),
    WebsiteIcon('video', 'Video camera', Icons.videocam_outlined, category: _m, keywords: ['film', 'record']),
    WebsiteIcon('play', 'Play', Icons.play_circle_outline, category: _m, keywords: ['video', 'start']),
    WebsiteIcon('video_channel', 'Video channel', Icons.smart_display_outlined, category: _m, keywords: ['youtube', 'video', 'watch']),
    WebsiteIcon('movie', 'Film', Icons.movie_outlined, category: _m, keywords: ['movie', 'video']),
    WebsiteIcon('microphone', 'Microphone', Icons.mic_none_outlined, category: _m, keywords: ['speak', 'audio']),
    WebsiteIcon('headphones', 'Headphones', Icons.headphones_outlined, category: _m, keywords: ['audio', 'listen']),
    WebsiteIcon('podcast', 'Podcast', Icons.podcasts, category: _m, keywords: ['audio', 'broadcast']),
    WebsiteIcon('download', 'Download', Icons.download_outlined, category: _m, keywords: ['save', 'file']),
    WebsiteIcon('upload', 'Upload', Icons.upload_outlined, category: _m, keywords: ['send', 'file']),
    WebsiteIcon('share', 'Share', Icons.share_outlined, category: _m, keywords: ['social']),
    WebsiteIcon('website', 'Website', Icons.language, category: _m, keywords: ['web', 'internet', 'site']),
    WebsiteIcon('rss', 'News feed', Icons.rss_feed, category: _m, keywords: ['rss', 'blog', 'updates']),
    WebsiteIcon('qr_code', 'QR code', Icons.qr_code_2, category: _m, keywords: ['scan']),
    WebsiteIcon('facebook', 'Facebook', Icons.facebook, category: _m, keywords: ['social']),
    WebsiteIcon('telegram', 'Telegram', Icons.telegram, category: _m, keywords: ['social', 'chat']),
  ];
}
