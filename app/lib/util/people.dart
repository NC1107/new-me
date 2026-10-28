/// [items] with the signed-in person's entry first and the rest in their given order.
List<T> meFirst<T>(Iterable<T> items, int? myId, int Function(T item) idOf) {
  final list = items.toList();
  final mine = list.where((i) => idOf(i) == myId).toList();
  return [...mine, ...list.where((i) => idOf(i) != myId)];
}
