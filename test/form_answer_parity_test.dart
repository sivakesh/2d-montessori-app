// The app's answer validation gives exactly the values and errors in
// test/fixtures/form_answer_cases.json. The submission endpoint
// (functions/src/answers.js) is tested against the same file
// (functions/test/answers.test.js), so the browser's messages and the
// endpoint's decisions can't drift apart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/forms/models/website_form.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/form_answer_cases.json').readAsStringSync()) as Map<String, dynamic>;
  final forms = fixture['forms'] as Map<String, dynamic>;
  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test('answers: ${c['name']}', () {
      final fields = [for (final f in forms[c['form']] as List) WebsiteFormField.fromMap(f)];
      final result = validateFormAnswers(fields, Map<String, Object?>.from(c['answers'] as Map));
      expect(result.values, c['values']);
      expect({for (final e in result.errors.entries) e.key: e.value.name}, c['errors']);
    });
  }
}
