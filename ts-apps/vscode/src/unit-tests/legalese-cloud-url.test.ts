import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import { isLegaleseCloudUrl } from '../legalese-cloud-url.js'

describe('isLegaleseCloudUrl', () => {
  test('accepts https to legalese.cloud and its subdomains', () => {
    for (const url of [
      'https://legalese.cloud/auth/session',
      'https://api.legalese.cloud/acme/deployments',
      'https://mcp.legalese.cloud/acme',
      'https://ai.legalese.cloud',
      'https://sessions.legalese.cloud:443/sessions',
      'HTTPS://AI.LEGALESE.CLOUD/v1/usage',
    ]) {
      assert.equal(isLegaleseCloudUrl(url), true, url)
    }
  })

  test('refuses everything else', () => {
    for (const url of [
      'http://legalese.cloud/auth/session',
      'http://127.0.0.1:3000/v1/chat/completions',
      'https://legalese.cloud.evil.example/',
      'https://evillegalese.cloud/',
      'https://evil.example/?legalese.cloud',
      'https://legalese.cloud@evil.example/',
      'https://user:pass@api.legalese.cloud/',
      'https://api.legalese.cloud:8443/',
      'https://legalese.com/console',
      'wss://ai.legalese.cloud/',
      'not a url',
      '',
    ]) {
      assert.equal(isLegaleseCloudUrl(url), false, url)
    }
  })
})
