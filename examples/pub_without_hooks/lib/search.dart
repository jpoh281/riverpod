import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'detail.dart';
import 'pub_repository.dart';
import 'pub_ui/appbar.dart';
import 'pub_ui/package_item.dart';
import 'pub_ui/searchbar.dart';

part 'search.g.dart';

const packagesPackageSize = 100;
const searchPageSize = 10;

@riverpod
Future<List<Package>> fetchPackages(
  FetchPackagesRef ref, {
  required int page,
  String search = '',
}) async {
  assert(page > 0, 'page offset starts at 1');
  final cancelToken = ref.cancelToken();

  if (search.isEmpty) {
    return ref
        .watch(pubRepositoryProvider)
        .getPackages(page: page, cancelToken: cancelToken);
  }

  // Debouncing searches by delaying the request.
  // If the search was cancelled during this delay, the network request will
  // not be performed.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (cancelToken.isCancelled) {
    throw Exception('cancelled');
  }

  final searchedPackages = await ref
      .watch(pubRepositoryProvider)
      .searchPackages(page: page, search: search, cancelToken: cancelToken);

  return Future.wait([
    for (final package in searchedPackages)
      ref.watch(
        FetchPackageDetailsProvider(packageName: package.package).future,
      ),
  ]);
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    searchController.addListener(rebuild);
  }

  @override
  dispose() {
    searchController.removeListener(rebuild);
    searchController.dispose();
    super.dispose();
  }

  rebuild() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PubAppbar(),
      body: Column(
        children: [
          SearchBar(controller: searchController),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () {
                // disposes the pages previously fetched. Next read will refresh them
                ref.invalidate(fetchPackagesProvider);
                // keep showing the progress indicator until the first page is fetched
                return ref.read(
                  fetchPackagesProvider(page: 1, search: searchController.text)
                      .future,
                );
              },
              child: ListView.custom(
                padding: const EdgeInsets.only(top: 30),
                childrenDelegate: SliverChildBuilderDelegate((context, index) {
                  final pageSize = searchController.text.isEmpty
                      ? packagesPackageSize
                      : searchPageSize;

                  final page = index ~/ pageSize + 1;
                  final indexInPage = index % pageSize;
                  final packageList = ref.watch(
                    fetchPackagesProvider(
                      page: page,
                      search: searchController.text,
                    ),
                  );

                  return packageList.when(
                    error: (err, stack) => Text('Error $err'),
                    loading: () => const PackageItemShimmer(),
                    data: (packages) {
                      if (indexInPage >= packages.length) return null;

                      final package = packages[indexInPage];

                      return PackageItem(
                        name: package.name,
                        description: package.latest.pubspec.description,
                        version: package.latest.version,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (context) {
                              return PackageDetailPage(
                                packageName: package.name,
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
