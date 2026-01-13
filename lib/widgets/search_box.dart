// // lib/widgets/search_box.dart

// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../providers/market_provider.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// class SearchBox extends StatefulWidget {
//   const SearchBox({Key? key}) : super(key: key);

//   @override
//   _SearchBoxState createState() => _SearchBoxState();
// }

// class _SearchBoxState extends State<SearchBox> {
//   late TextEditingController _controller;
//   late FocusNode _focusNode;

//   @override
//   void initState() {
//     super.initState();
//     final marketProvider = Provider.of<MarketProvider>(context, listen: false);
//     _controller = TextEditingController(text: marketProvider.searchTerm);
//     _focusNode = FocusNode();
//     _focusNode.addListener(() {
//       if (!_focusNode.hasFocus) {
//         // Optionally perform actions when focus is lost
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     _focusNode.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final marketProvider = Provider.of<MarketProvider>(context, listen: false);

//     return Padding(
//       padding: const EdgeInsets.all(8.0),
//       child: Card(
//         color: Colors.transparent,
//         elevation: 0,
//         shape: RoundedRectangleBorder(
//           side: BorderSide(color: Colors.grey.withOpacity(0.5)),
//           borderRadius: BorderRadius.circular(8),
//         ),
//         child: TextField(
//           controller: _controller,
//           focusNode: _focusNode,
//           textAlignVertical: TextAlignVertical.center, // Correct placement
//           onChanged: (value) => marketProvider.setSearchTerm(value),
//           decoration: InputDecoration(
//             hintText: AppLocalizations.of(context)!.searchProducts,
//             border: InputBorder.none,
//             prefixIcon: const Icon(Icons.search),
//             contentPadding:
//                 const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
//           ),
//         ),
//       ),
//     );
//   }
// }
