// A stand-in for the phone's text reader, which only a phone has.

import 'dart:typed_data';

import 'package:dinner_planner/data/labels.dart';

List<LabelLine> lines(List<(String, double)> read) => [for (final (text, height) in read) (text: text, height: height)];

/// A picture that is only a number, for [FakeLabels.frames] to know it by.
Uint8List frame(int n) => Uint8List.fromList([n]);

/// Each picture reads as whatever [frames] says for its number; [photos] are
/// what the next photographs read as (none left: the person backed out of
/// the camera).
class FakeLabels implements LabelCamera {
  final Map<int, List<LabelLine>> frames = {};
  final List<List<LabelLine>?> photos = [];
  int photographed = 0;

  @override
  Future<List<LabelLine>> read(Uint8List picture) async => frames[picture.first] ?? const [];

  @override
  Future<List<LabelLine>?> photograph() async {
    photographed++;
    return photos.isEmpty ? null : photos.removeAt(0);
  }
}
