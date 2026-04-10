// functions/shared/isbank-void.js
//
// Isbank Nestpay Void & Refund helper.
// Tries Void first (same-day cancellation, no amount needed).
// Falls back to Credit (refund) if Void fails - requires amount.
//
// Endpoint: https://spos.isbank.com.tr/fim/api  (XML API)
// Docs: Is Bankasi Api Dokumani - CC5Request format

const ISBANK_API_URL = 'https://spos.isbank.com.tr/fim/api';

function escapeXml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function buildCC5Request({ type, orderId, amount, currency = '949' }) {
  const clientId = process.env.ISBANK_CLIENT_ID;
  const apiUser = process.env.ISBANK_API_USER;
  const apiPassword = process.env.ISBANK_API_PASSWORD;

  const nameTag = '<' + 'Name' + '>';
  const nameCloseTag = '</' + 'Name' + '>';

  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
  xml += '<CC5Request>\n';
  xml += `  ${nameTag}${escapeXml(apiUser)}${nameCloseTag}\n`;
  xml += `  <Password>${escapeXml(apiPassword)}</Password>\n`;
  xml += `  <ClientId>${escapeXml(clientId)}</ClientId>\n`;
  xml += `  <Type>${escapeXml(type)}</Type>\n`;
  xml += `  <OrderId>${escapeXml(orderId)}</OrderId>\n`;

  if (type === 'Credit' && amount) {
    xml += `  <Total>${escapeXml(amount)}</Total>\n`;
    xml += `  <Currency>${escapeXml(currency)}</Currency>\n`;
  }

  xml += '</CC5Request>';
  return xml;
}

function parseCC5Response(xml) {
  const extract = (tag) => {
    const match = xml.match(new RegExp(`<${tag}>([^<]*)</${tag}>`));
    return match ? match[1] : null;
  };

  return {
    response: extract('Response'),            // 'Approved' | 'Declined' | 'Error'
    procReturnCode: extract('ProcReturnCode'), // '00' = success
    orderId: extract('OrderId'),
    transId: extract('TransId'),
    authCode: extract('AuthCode'),
    hostRefNum: extract('HostRefNum'),
    errMsg: extract('ErrMsg'),
  };
}

async function sendCC5Request(xmlBody) {
  const response = await fetch(ISBANK_API_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'text/xml; charset=UTF-8' },
    body: xmlBody,
  });

  if (!response.ok) {
    throw new Error(`Isbank API HTTP error: ${response.status} ${response.statusText}`);
  }

  const responseText = await response.text();
  return parseCC5Response(responseText);
}

export async function reversePayment(orderId, amount, currency = '949') {
  // Step 1: Try Void
  try {
    const voidXml = buildCC5Request({ type: 'Void', orderId });
    const voidResult = await sendCC5Request(voidXml);

    if (voidResult.response === 'Approved' && voidResult.procReturnCode === '00') {
      console.log(`[Reversal] Void successful for ${orderId}`);
      return { success: true, method: 'void', response: voidResult };
    }

    console.warn(`[Reversal] Void declined for ${orderId}: ${voidResult.errMsg} (code: ${voidResult.procReturnCode})`);
  } catch (voidError) {
    console.error(`[Reversal] Void request failed for ${orderId}:`, voidError.message);
  }

  // Step 2: Fallback to Credit (refund)
  try {
    const formattedAmount = String(amount);
    const creditXml = buildCC5Request({
      type: 'Credit',
      orderId,
      amount: formattedAmount,
      currency,
    });
    const creditResult = await sendCC5Request(creditXml);

    if (creditResult.response === 'Approved' && creditResult.procReturnCode === '00') {
      console.log(`[Reversal] Credit (refund) successful for ${orderId}`);
      return { success: true, method: 'credit', response: creditResult };
    }

    const errMsg = `Credit also failed: ${creditResult.errMsg} (code: ${creditResult.procReturnCode})`;
    console.error(`[Reversal] ${errMsg}`);
    return { success: false, method: null, response: creditResult, error: errMsg };
  } catch (creditError) {
    const errMsg = `Both void and credit failed for ${orderId}: ${creditError.message}`;
    console.error(`[Reversal] ${errMsg}`);
    return { success: false, method: null, response: null, error: errMsg };
  }
}
