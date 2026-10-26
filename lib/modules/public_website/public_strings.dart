import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'public_routes.dart';

/// A language of the public website: its code (`en`, `ta`, `hi`, …), its
/// names, and the language its managed text falls back to when it has
/// none. Two languages are equal when their codes are. [english] and
/// [tamil] are the built-in languages; others come from the website's
/// language registry (Settings → Website → Languages).
@immutable
class PublicLanguage {
  const PublicLanguage(this.code, {required this.nativeName, required this.englishName, String? shortLabel, this.fallbackCode = 'en'})
      : _shortLabel = shortLabel;

  static const english = PublicLanguage('en', nativeName: 'English', englishName: 'English', shortLabel: 'EN');
  static const tamil = PublicLanguage('ta', nativeName: 'தமிழ்', englishName: 'Tamil');

  /// The languages offered when no language registry is published.
  static const builtIn = [english, tamil];

  /// The source language: every managed text has it.
  static const sourceCode = 'en';

  /// ISO-style code: `en`, `ta`, `hi`, `pt-BR`, …
  final String code;

  /// The language's name in itself (தமிழ், हिन्दी, Français).
  final String nativeName;
  final String englishName;
  final String? _shortLabel;

  /// Where this language's managed text falls back to (then English).
  final String fallbackCode;

  /// Shown on the switch: "EN" for English, otherwise the native name.
  String get shortLabel => _shortLabel ?? nativeName;

  /// Accessible name, e.g. for the switch's semantics.
  String get label => englishName;

  /// A stable name for widget keys (`english`, `tamil`, or the code).
  String get name => switch (code) { 'en' => 'english', 'ta' => 'tamil', _ => code };

  PublicLanguage withFallback(String fallback) =>
      PublicLanguage(code, nativeName: nativeName, englishName: englishName, shortLabel: _shortLabel, fallbackCode: fallback);

  @override
  bool operator ==(Object other) => other is PublicLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'PublicLanguage($code)';
}

/// The selected public-site language (in memory for this session).
final publicLanguageProvider = StateProvider<PublicLanguage>((ref) => PublicLanguage.english);

/// Copy for the public website in each language. Kept to general,
/// Montessori-method wording and site navigation: no school facts
/// (credentials, fees, dates, contact details, results) are stated, as none
/// are confirmed yet. Tamil wording should be reviewed by a native speaker
/// before launch.
class PublicStrings {
  const PublicStrings._(this._t);

  factory PublicStrings.of(PublicLanguage language) => language == PublicLanguage.tamil ? _tamil : _english;

  final Map<String, String> _t;

  String _get(String key) => _t[key] ?? _english._t[key]!;

  String get schoolName => _get('schoolName');
  String get home => _get('home');
  String get admissions => _get('admissions');
  String get teacherTraining => _get('teacherTraining');
  String get programs => _get('programs');
  String get gallery => _get('gallery');
  String get contact => _get('contact');
  String get login => _get('login');
  String get dashboard => _get('dashboard');
  String get logout => _get('logout');
  String get menu => _get('menu');
  String get language => _get('language');
  String get heroEyebrow => _get('heroEyebrow');
  String get heroTitle => _get('heroTitle');
  String get heroBody => _get('heroBody');
  String get pathwaysTitle => _get('pathwaysTitle');
  String get familiesTitle => _get('familiesTitle');
  String get familiesBody => _get('familiesBody');
  String get familiesCta => _get('familiesCta');
  String get educatorsTitle => _get('educatorsTitle');
  String get educatorsBody => _get('educatorsBody');
  String get educatorsCta => _get('educatorsCta');
  String get approachEyebrow => _get('approachEyebrow');
  String get approachTitle => _get('approachTitle');
  String get principleChildTitle => _get('principleChildTitle');
  String get principleChildBody => _get('principleChildBody');
  String get principleEnvironmentTitle => _get('principleEnvironmentTitle');
  String get principleEnvironmentBody => _get('principleEnvironmentBody');
  String get principleIndependenceTitle => _get('principleIndependenceTitle');
  String get principleIndependenceBody => _get('principleIndependenceBody');
  String get comingSoonTitle => _get('comingSoonTitle');
  String get comingSoonBody => _get('comingSoonBody');
  String get backHome => _get('backHome');
  String get footerTagline => _get('footerTagline');
  String get footerStaff => _get('footerStaff');
  String get galleryIntro => _get('galleryIntro');
  String get galleryAll => _get('galleryAll');
  String get galleryFilterLabel => _get('galleryFilterLabel');
  String get galleryLoading => _get('galleryLoading');
  String get galleryEmptyTitle => _get('galleryEmptyTitle');
  String get galleryEmptyBody => _get('galleryEmptyBody');
  String get galleryCategoryEmpty => _get('galleryCategoryEmpty');
  String get galleryErrorTitle => _get('galleryErrorTitle');
  String get galleryErrorBody => _get('galleryErrorBody');
  String get galleryRetry => _get('galleryRetry');
  String get galleryShowMore => _get('galleryShowMore');
  String get galleryClose => _get('galleryClose');
  String get galleryPrevious => _get('galleryPrevious');
  String get galleryNext => _get('galleryNext');
  String get galleryOpenImage => _get('galleryOpenImage');
  String get imageUnavailable => _get('imageUnavailable');
  String get pageNotFoundTitle => _get('pageNotFoundTitle');
  String get pageNotFoundBody => _get('pageNotFoundBody');
  String get pageLoadErrorTitle => _get('pageLoadErrorTitle');
  String get pageLoadErrorBody => _get('pageLoadErrorBody');
  String get pageLoading => _get('pageLoading');

  /// "3 of 12" in the lightbox.
  String galleryPosition(int current, int total) => _get('galleryPosition').replaceAll('{current}', '$current').replaceAll('{total}', '$total');

  /// Navigation label for a public route.
  String labelFor(String route) => switch (route) {
        PublicRoutes.home => home,
        PublicRoutes.admissions => admissions,
        PublicRoutes.teacherTraining => teacherTraining,
        PublicRoutes.programs => programs,
        PublicRoutes.gallery => gallery,
        PublicRoutes.contact => contact,
        _ => route,
      };

  /// One-line introduction for a section page that isn't built yet.
  String introFor(String route) => switch (route) {
        PublicRoutes.admissions => _get('admissionsIntro'),
        PublicRoutes.teacherTraining => _get('teacherTrainingIntro'),
        PublicRoutes.programs => _get('programsIntro'),
        PublicRoutes.gallery => galleryIntro,
        PublicRoutes.contact => _get('contactIntro'),
        _ => '',
      };

  static const _english = PublicStrings._({
    'schoolName': '2D Montessori',
    'home': 'Home',
    'admissions': 'Admissions',
    'teacherTraining': 'Teacher Training',
    'programs': 'Programs',
    'gallery': 'Gallery',
    'contact': 'Contact',
    'login': 'Login',
    'dashboard': 'Dashboard',
    'logout': 'Logout',
    'menu': 'Menu',
    'language': 'Language',
    'heroEyebrow': 'MONTESSORI EDUCATION',
    'heroTitle': 'A calm, thoughtful place to learn and grow',
    'heroBody': 'Welcome to 2D Montessori. Whether you are a family looking for a Montessori start for your child '
        'or an educator exploring Montessori practice, begin here.',
    'pathwaysTitle': 'How can we help you?',
    'familiesTitle': 'For Families',
    'familiesBody': 'Learn about our programs and how admissions work.',
    'familiesCta': 'Explore admissions',
    'educatorsTitle': 'For Educators',
    'educatorsBody': 'Discover Montessori teacher training and how to take part.',
    'educatorsCta': 'Explore teacher training',
    'approachEyebrow': 'THE MONTESSORI APPROACH',
    'approachTitle': 'Guided by the Montessori method',
    'principleChildTitle': 'Follow the child',
    'principleChildBody': 'Learning that responds to each child’s interests, pace and readiness.',
    'principleEnvironmentTitle': 'A prepared environment',
    'principleEnvironmentBody': 'Orderly, purposeful spaces with materials children can explore on their own.',
    'principleIndependenceTitle': 'Independence and care',
    'principleIndependenceBody': 'Everyday practice in doing things for oneself and caring for others.',
    'admissionsIntro': 'Information about admissions will be published here.',
    'teacherTrainingIntro': 'Information about Montessori teacher training will be published here.',
    'programsIntro': 'Information about our programs will be published here.',
    'contactIntro': 'Contact details will be published here.',
    'comingSoonTitle': 'This page is being prepared',
    'comingSoonBody': 'Please check back soon.',
    'backHome': 'Back to Home',
    'footerTagline': 'Montessori education for children and educators.',
    'footerStaff': 'For staff and school management',
    'galleryIntro': 'Photographs shared by 2D Montessori.',
    'galleryAll': 'All',
    'galleryFilterLabel': 'Filter photographs by category',
    'galleryLoading': 'Loading photographs',
    'galleryEmptyTitle': 'Photographs are on their way',
    'galleryEmptyBody': 'The school will share photographs here soon.',
    'galleryCategoryEmpty': 'There are no photographs in this category yet.',
    'galleryErrorTitle': 'The gallery could not be loaded',
    'galleryErrorBody': 'Please check your connection and try again.',
    'galleryRetry': 'Try again',
    'galleryShowMore': 'Show more photographs',
    'galleryClose': 'Close',
    'galleryPrevious': 'Previous photograph',
    'galleryNext': 'Next photograph',
    'galleryOpenImage': 'Open photograph',
    'galleryPosition': '{current} of {total}',
    'imageUnavailable': 'Image unavailable',
    'pageNotFoundTitle': 'Page not found',
    'pageNotFoundBody': 'This page does not exist or is no longer available.',
    'pageLoadErrorTitle': 'This page could not be loaded',
    'pageLoadErrorBody': 'Please check your connection and try again.',
    'pageLoading': 'Loading page',
  });

  static const _tamil = PublicStrings._({
    'home': 'முகப்பு',
    'admissions': 'சேர்க்கை',
    'teacherTraining': 'ஆசிரியர் பயிற்சி',
    'programs': 'திட்டங்கள்',
    'gallery': 'படத்தொகுப்பு',
    'contact': 'தொடர்பு',
    'login': 'உள்நுழைவு',
    'dashboard': 'டாஷ்போர்டு',
    'logout': 'வெளியேறு',
    'menu': 'பட்டியல்',
    'language': 'மொழி',
    'heroEyebrow': 'மாண்டிசோரி கல்வி',
    'heroTitle': 'கற்கவும் வளரவும் அமைதியான, அக்கறையுள்ள இடம்',
    'heroBody': '2D மாண்டிசோரிக்கு வரவேற்கிறோம். உங்கள் குழந்தைக்கு மாண்டிசோரி தொடக்கத்தைத் தேடும் குடும்பமாக இருந்தாலும், '
        'மாண்டிசோரி முறையை அறிய விரும்பும் கல்வியாளராக இருந்தாலும், இங்கிருந்து தொடங்குங்கள்.',
    'pathwaysTitle': 'நாங்கள் எவ்வாறு உதவலாம்?',
    'familiesTitle': 'குடும்பங்களுக்கு',
    'familiesBody': 'எங்கள் திட்டங்கள் மற்றும் சேர்க்கை முறை பற்றி அறியுங்கள்.',
    'familiesCta': 'சேர்க்கை பற்றி அறிய',
    'educatorsTitle': 'கல்வியாளர்களுக்கு',
    'educatorsBody': 'மாண்டிசோரி ஆசிரியர் பயிற்சி மற்றும் அதில் பங்கேற்கும் முறையை அறியுங்கள்.',
    'educatorsCta': 'ஆசிரியர் பயிற்சி பற்றி அறிய',
    'approachEyebrow': 'மாண்டிசோரி அணுகுமுறை',
    'approachTitle': 'மாண்டிசோரி முறையின் வழிகாட்டுதலில்',
    'principleChildTitle': 'குழந்தையைப் பின்பற்றுதல்',
    'principleChildBody': 'ஒவ்வொரு குழந்தையின் ஆர்வம், வேகம் மற்றும் தயார்நிலைக்கு ஏற்ற கற்றல்.',
    'principleEnvironmentTitle': 'தயார்படுத்தப்பட்ட சூழல்',
    'principleEnvironmentBody': 'குழந்தைகள் தாமாக ஆராயக்கூடிய பொருட்களுடன் ஒழுங்கான, நோக்கமுள்ள இடங்கள்.',
    'principleIndependenceTitle': 'சுயசார்பும் அக்கறையும்',
    'principleIndependenceBody': 'தங்கள் வேலைகளைத் தாமே செய்வதிலும் பிறரைக் கவனிப்பதிலும் அன்றாடப் பயிற்சி.',
    'admissionsIntro': 'சேர்க்கை பற்றிய தகவல்கள் இங்கே வெளியிடப்படும்.',
    'teacherTrainingIntro': 'மாண்டிசோரி ஆசிரியர் பயிற்சி பற்றிய தகவல்கள் இங்கே வெளியிடப்படும்.',
    'programsIntro': 'எங்கள் திட்டங்கள் பற்றிய தகவல்கள் இங்கே வெளியிடப்படும்.',
    'contactIntro': 'தொடர்பு விவரங்கள் இங்கே வெளியிடப்படும்.',
    'comingSoonTitle': 'இந்தப் பக்கம் தயாராகிக் கொண்டிருக்கிறது',
    'comingSoonBody': 'விரைவில் மீண்டும் பார்வையிடுங்கள்.',
    'backHome': 'முகப்புக்குத் திரும்ப',
    'footerTagline': 'குழந்தைகளுக்கும் கல்வியாளர்களுக்கும் மாண்டிசோரி கல்வி.',
    'footerStaff': 'பணியாளர்கள் மற்றும் பள்ளி நிர்வாகத்திற்கு',
    'galleryIntro': '2D மாண்டிசோரி பகிர்ந்த புகைப்படங்கள்.',
    'galleryAll': 'அனைத்தும்',
    'galleryFilterLabel': 'வகை வாரியாகப் புகைப்படங்களை வடிகட்டு',
    'galleryLoading': 'புகைப்படங்கள் ஏற்றப்படுகின்றன',
    'galleryEmptyTitle': 'புகைப்படங்கள் விரைவில்',
    'galleryEmptyBody': 'பள்ளி விரைவில் இங்கே புகைப்படங்களைப் பகிரும்.',
    'galleryCategoryEmpty': 'இந்த வகையில் இன்னும் புகைப்படங்கள் இல்லை.',
    'galleryErrorTitle': 'படத்தொகுப்பை ஏற்ற முடியவில்லை',
    'galleryErrorBody': 'உங்கள் இணைப்பைச் சரிபார்த்து மீண்டும் முயலுங்கள்.',
    'galleryRetry': 'மீண்டும் முயல்க',
    'galleryShowMore': 'மேலும் புகைப்படங்கள்',
    'galleryClose': 'மூடு',
    'galleryPrevious': 'முந்தைய புகைப்படம்',
    'galleryNext': 'அடுத்த புகைப்படம்',
    'galleryOpenImage': 'புகைப்படத்தைத் திற',
    'galleryPosition': '{total} இல் {current}',
    'imageUnavailable': 'படம் கிடைக்கவில்லை',
    'pageNotFoundTitle': 'பக்கம் கிடைக்கவில்லை',
    'pageNotFoundBody': 'இந்தப் பக்கம் இல்லை அல்லது இனி கிடைக்காது.',
    'pageLoadErrorTitle': 'இந்தப் பக்கத்தை ஏற்ற முடியவில்லை',
    'pageLoadErrorBody': 'உங்கள் இணைப்பைச் சரிபார்த்து மீண்டும் முயலுங்கள்.',
    'pageLoading': 'பக்கம் ஏற்றப்படுகிறது',
  });
}
