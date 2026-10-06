import 'package:bref/bref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trame/testing.dart';
import 'package:trame/trame.dart';

void main() {
  late FakeHub hub;
  late DocSession mine;
  late DocSession theirs;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(hub.settle);
    await tester.pump();
  }

  Future<void> pump(WidgetTester tester, BrefFollow follow) async {
    hub = FakeHub([for (var i = 0; i < 200; i++) 'line $i'].join('\n'));
    mine = DocSession(hub.connect)..start();
    theirs = DocSession(hub.connect)..start();
    addTearDown(mine.dispose);
    addTearDown(theirs.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrefEditor(session: mine, follow: follow))));
    await settle(tester);
  }

  double scrolled(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  testWidgets('the view goes where the person followed is, until this person takes the lead', (tester) async {
    final follow = BrefFollow();
    addTearDown(follow.dispose);
    await pump(tester, follow);
    expect(scrolled(tester), 0);

    theirs.select(const DocSelection.collapsed('body', 1000));
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
    expect(scrolled(tester), 0, reason: 'not following yet');

    follow.follow(mine.peers.single.sid);
    await tester.pump();
    final there = scrolled(tester);
    expect(there, greaterThan(0));

    theirs.select(const DocSelection.collapsed('body', 20));
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
    expect(scrolled(tester), lessThan(there));

    await tester.tapAt(const Offset(200, 100));
    expect(follow.sid, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
