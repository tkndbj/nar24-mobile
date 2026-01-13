const { algoliasearch, instantsearch } = window;

const searchClient = algoliasearch(
  '3QVVGQH4ME',
  'dcca6685e21c2baed748ccea7a6ddef1'
);

const search = instantsearch({
  indexName: 'products',
  searchClient,
  future: { preserveSharedStateOnUnmount: true },
});

search.addWidgets([
  instantsearch.widgets.searchBox({
    container: '#searchbox',
  }),
  instantsearch.widgets.hits({
    container: '#hits',
    templates: {
      item: (hit, { html, components }) => html`
        <article>
          <img src=${hit.imageUrls[0]} alt=${hit.productName} />
          <div>
            <h1>${components.Highlight({ hit, attribute: 'productName' })}</h1>
            <p>${components.Highlight({ hit, attribute: 'brandModel' })}</p>
            <p>${components.Highlight({ hit, attribute: 'description' })}</p>
          </div>
        </article>
      `,
    },
  }),
  instantsearch.widgets.configure({
    hitsPerPage: 8,
  }),
  instantsearch.widgets.pagination({
    container: '#pagination',
  }),
]);

search.start();
