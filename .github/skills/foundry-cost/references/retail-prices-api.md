# Retail Prices API notes for Microsoft Foundry costs

Use the Azure Retail Prices API for live public meter data, but do not assume portal
or product branding maps directly to API fields.

Endpoint:

```text
https://prices.azure.com/api/retail/prices
```

## Gotchas observed for this repo

- `serviceName eq 'Microsoft Foundry'` can return no rows. Do not stop there.
- Foundry model meters can appear under `serviceName = 'Foundry Models'`.
- The `productName` under `Foundry Models` can still contain `Azure OpenAI` even when
  you are pricing a Microsoft Foundry model meter. Treat that as billing taxonomy,
  not a reason to link to Azure OpenAI pricing as Foundry guidance.
- Azure AI Search can appear under `serviceName = 'Azure Cognitive Search'`.
- Meter names can be abbreviated, for example `5.4 inp Gl 1M Tokens`; inspect
  `meterName`, `skuName`, `unitOfMeasure`, and region before using a price.

## Query patterns

Foundry model meters in a region:

```bash
curl -sG 'https://prices.azure.com/api/retail/prices' \
  --data-urlencode "\$filter=armRegionName eq 'japaneast' and serviceName eq 'Foundry Models'" \
  | jq -r '.Items[] | [.serviceName,.productName,.skuName,.meterName,.unitOfMeasure,.retailPrice,.currencyCode] | @tsv'
```

Model-family narrowing:

```bash
curl -sG 'https://prices.azure.com/api/retail/prices' \
  --data-urlencode "\$filter=armRegionName eq 'japaneast' and serviceName eq 'Foundry Models' and contains(meterName, '5.4')" \
  | jq -r '.Items[] | [.serviceName,.productName,.skuName,.meterName,.unitOfMeasure,.retailPrice,.currencyCode] | @tsv'
```

Azure AI Search meters:

```bash
curl -sG 'https://prices.azure.com/api/retail/prices' \
  --data-urlencode "\$filter=armRegionName eq 'japaneast' and serviceName eq 'Azure Cognitive Search'" \
  | jq -r '.Items[] | [.serviceName,.productName,.skuName,.meterName,.unitOfMeasure,.retailPrice,.currencyCode] | @tsv'
```

Log Analytics ingestion/retention meters:

```bash
curl -sG 'https://prices.azure.com/api/retail/prices' \
  --data-urlencode "\$filter=armRegionName eq 'japaneast' and contains(productName, 'Log Analytics')" \
  | jq -r '.Items[] | [.serviceName,.productName,.skuName,.meterName,.unitOfMeasure,.retailPrice,.currencyCode] | @tsv'
```
