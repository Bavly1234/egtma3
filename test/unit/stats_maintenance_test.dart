import 'package:egtma3/core/constants/firestore_paths.dart';
import 'package:egtma3/features/statistics/data/stats_maintenance.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('after deleting women, statistics only count the women that exist', () async {
    final db = FakeFirebaseFirestore();
    // One real woman left; the test women were already deleted.
    await db.collection(FsPaths.women).doc('real').set({'fullName': 'سيدة', 'streetId': 's1'});
    await db.collection(FsPaths.streets).doc('s1').set({'name': 'ش', 'womenCount': 7});
    Future<void> att(String meeting, String woman, String status) => db
        .collection(FsPaths.attendance)
        .doc('${meeting}_$woman')
        .set({'meetingId': meeting, 'womanId': woman, 'status': status,
              'streetId': 's1', 'servantId': 'sv'});
    await att('2026-10-07', 'real', 'absent');
    await att('2026-10-07', 'demo1', 'present'); // deleted woman
    await att('2026-09-30', 'demo2', 'present'); // meeting with only test data
    await db.collection(FsPaths.suggestions).doc('x').set({'womanId': 'demo1'});
    // Stale totals still counting the test women.
    await db.collection(FsPaths.meetings).doc('2026-10-07').set({
      'present': 18, 'absent': 5, 'autoAbsentDone': true,
      'byStreet': {'s1': {'present': 18, 'absent': 5}},
    });
    await db.collection(FsPaths.meetings).doc('2026-09-30').set({'present': 12, 'absent': 6});

    await StatsMaintenance(db).rebuild();

    final m = (await db.collection(FsPaths.meetings).doc('2026-10-07').get()).data()!;
    expect(m['present'], 0);
    expect(m['absent'], 1);
    expect(m['byStreet'], {'s1': {'present': 0, 'absent': 1}});
    expect(m['byServant'], {'sv': {'present': 0, 'absent': 1}});
    expect(m['autoAbsentDone'], true);
    expect((await db.collection(FsPaths.meetings).doc('2026-09-30').get()).exists, isFalse);
    expect((await db.collection(FsPaths.attendance).get()).size, 1);
    expect((await db.collection(FsPaths.suggestions).get()).size, 0);
    expect((await db.collection(FsPaths.streets).doc('s1').get()).get('womenCount'), 1);
  });

  test('with no women at all, every statistic goes to zero', () async {
    final db = FakeFirebaseFirestore();
    await db.collection(FsPaths.attendance).doc('a').set(
        {'meetingId': '2026-10-07', 'womanId': 'gone', 'status': 'present'});
    await db.collection(FsPaths.meetings).doc('2026-10-07').set({'present': 30, 'absent': 4});
    await db.collection(FsPaths.followUps).doc('f').set({'womanId': 'gone'});

    await StatsMaintenance(db).rebuild();

    expect((await db.collection(FsPaths.meetings).get()).size, 0);
    expect((await db.collection(FsPaths.attendance).get()).size, 0);
    expect((await db.collection(FsPaths.followUps).get()).size, 0);
  });
}
