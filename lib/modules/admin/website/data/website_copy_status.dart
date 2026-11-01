import 'package:flutter/material.dart';

import '../../../public_website/content/website_content_models.dart';

/// Where a school record (a calendar event or an announcement) stands on
/// the public website, judged from its sanitized copy in
/// `website_public_items`.
enum WebsiteCopyState {
  /// Not on the website.
  notShown,

  /// On the website, matching the record.
  current,

  /// On the website, but the record has been edited since: the website
  /// shows the older details until an admin updates or removes it.
  outOfDate,

  /// On the website, but the record can't be shown any more (no longer
  /// Published, no longer for everyone, or now sent to particular people):
  /// it should be removed.
  noLongerEligible,

  /// The copy is on the website, but visitors don't see it: it is over or
  /// expired, not yet due, or the copy isn't valid. Never reported as "On
  /// website".
  notVisible,
}

/// Where a record's website image stands, for the admin, by the media
/// library's own rules: visitors see an image only once it is published
/// with consent confirmed.
/// - Uploaded: in the library, but no alt text or consent confirmation yet.
/// - Approved: consent confirmed, not published yet.
/// - Published: visitors see it.
/// - Unavailable: deleted, hidden, or its consent withdrawn.
({String label, String detail, Color color, bool visible}) websiteImageStatus(String? mediaId, WebsiteMedia? media, {String what = 'event'}) {
  if (mediaId == null) return (label: 'No image', detail: 'Visitors see the $what without an image.', color: Colors.grey, visible: false);
  if (media == null) {
    return (label: 'Unavailable', detail: 'This image no longer exists. Choose another, or remove it.', color: Colors.redAccent, visible: false);
  }
  if (media.isPublished && media.consentConfirmed && media.url.isNotEmpty) {
    return (label: 'Published', detail: 'Visitors see this image with the $what.', color: const Color(0xFF2E7D5B), visible: true);
  }
  if (media.status == WebsiteMediaStatus.hidden || (media.isPublished && !media.consentConfirmed)) {
    return (
      label: 'Unavailable',
      detail: media.consentConfirmed
          ? 'Hidden from the website in the Media library, so visitors don’t see it. Publish it again, choose another, or remove it.'
          : 'Its consent was withdrawn, so visitors don’t see it. Choose another, or remove it.',
      color: Colors.redAccent,
      visible: false,
    );
  }
  if (media.consentConfirmed) {
    return (
      label: 'Approved',
      detail: 'Consent is confirmed, but it isn’t published yet. Publish it (Edit image) before saving.',
      color: Colors.orange,
      visible: false,
    );
  }
  return (
    label: 'Uploaded',
    detail: 'Needs English alt text and consent confirmation, then publishing (Edit image), before saving.',
    color: Colors.orange,
    visible: false,
  );
}
