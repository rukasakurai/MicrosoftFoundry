import {
  InteractionRequiredAuthError,
  PublicClientApplication,
  type AccountInfo,
} from '@azure/msal-browser'
import './style.css'

type RuntimeConfig = {
  authTenantId: string
  authClientId: string
  authScope: string
}

type ChatResponse = {
  responseId: string
  chatId: string
  text: string
  feedbackToken: string
  usage: TokenUsage
}

type TokenUsage = {
  limit: number
  used: number
  reserved: number
  remaining: number
  periodStart: string
  periodEnd: string
  observedAt: string
  consistency: string
}

type ApiError = {
  error?: string
  code?: string
  usage?: TokenUsage
}

class ApiRequestError extends Error {
  readonly code?: string
  readonly usage?: TokenUsage

  constructor(message: string, code?: string, usage?: TokenUsage) {
    super(message)
    this.name = 'ApiRequestError'
    this.code = code
    this.usage = usage
  }
}

const app = document.querySelector<HTMLElement>('#app')

if (!app) {
  throw new Error('Application root was not found.')
}

app.innerHTML = `
  <header class="app-header">
    <div>
      <p class="eyebrow">Microsoft Foundry</p>
      <h1>Foundry Guide</h1>
    </div>
    <nav class="account-actions" aria-label="Account">
      <span id="session-status">Loading...</span>
      <button id="sign-in" class="button secondary hidden" type="button">Sign in</button>
      <button id="sign-out" class="button secondary hidden" type="button">Sign out</button>
    </nav>
  </header>

  <section id="usage-panel" class="usage-panel hidden" aria-label="Monthly token usage">
    <div class="usage-summary">
      <span class="usage-label">Monthly token usage</span>
      <strong id="usage-value">Loading...</strong>
      <span id="usage-reset" class="usage-reset"></span>
    </div>
    <progress id="usage-progress" max="100" value="0">0%</progress>
  </section>

  <section class="chat-shell" aria-label="Foundry Guide chat">
    <div id="messages" class="messages" aria-live="polite">
      <article class="message assistant">
        <p>Ask a question about Microsoft Foundry.</p>
      </article>
    </div>

    <form id="chat-form" class="composer">
      <label for="prompt">Message</label>
      <textarea
        id="prompt"
        name="prompt"
        rows="3"
        maxlength="8000"
        placeholder="Ask Foundry Guide"
        required
      ></textarea>
      <div class="composer-actions">
        <button id="new-chat" class="button secondary" type="button">New chat</button>
        <button id="send" class="button primary" type="submit">Send</button>
      </div>
    </form>
  </section>
`

const chatForm = requireElement<HTMLFormElement>('chat-form')
const promptInput = requireElement<HTMLTextAreaElement>('prompt')
const messages = requireElement<HTMLDivElement>('messages')
const sendButton = requireElement<HTMLButtonElement>('send')
const newChatButton = requireElement<HTMLButtonElement>('new-chat')
const sessionStatus = requireElement<HTMLSpanElement>('session-status')
const signInButton = requireElement<HTMLButtonElement>('sign-in')
const signOutButton = requireElement<HTMLButtonElement>('sign-out')
const usagePanel = requireElement<HTMLElement>('usage-panel')
const usageValue = requireElement<HTMLElement>('usage-value')
const usageReset = requireElement<HTMLElement>('usage-reset')
const usageProgress = requireElement<HTMLProgressElement>('usage-progress')

let authClient: PublicClientApplication
let authScope: string
let account: AccountInfo | undefined
let previousResponseId: string | undefined
let chatId: string | undefined
let quotaExhausted = false
let requestBusy = false

chatForm.addEventListener('submit', async (event) => {
  event.preventDefault()

  const prompt = promptInput.value.trim()
  if (!account || !prompt) {
    return
  }

  appendMessage('user', prompt)
  promptInput.value = ''
  setBusy(true)

  try {
    const response = await authenticatedRequest<ChatResponse>('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        input: prompt,
        previousResponseId,
        chatId,
      }),
    })

    previousResponseId = response.responseId
    chatId = response.chatId
    renderUsage(response.usage)
    appendAssistantMessage(response.text, response.feedbackToken)
  } catch (error) {
    if (error instanceof ApiRequestError && error.usage) {
      renderUsage(error.usage)
    }
    appendMessage('error', error instanceof Error ? error.message : 'The request failed.')
  } finally {
    setBusy(false)
    promptInput.focus()
  }
})

newChatButton.addEventListener('click', () => {
  previousResponseId = undefined
  chatId = undefined
  messages.replaceChildren()
  appendMessage('assistant', 'Started a new chat.')
  promptInput.focus()
})

signInButton.addEventListener('click', () => {
  void authClient.loginRedirect({ scopes: [authScope] })
})

signOutButton.addEventListener('click', () => {
  if (account) {
    void authClient.logoutRedirect({
      account,
      postLogoutRedirectUri: window.location.origin,
    })
  }
})

void initialize()

async function initialize(): Promise<void> {
  try {
    const config = await requestJson<RuntimeConfig>('/api/config')
    authScope = config.authScope
    authClient = new PublicClientApplication({
      auth: {
        clientId: config.authClientId,
        authority: `https://login.microsoftonline.com/${config.authTenantId}`,
        redirectUri: window.location.origin,
        postLogoutRedirectUri: window.location.origin,
      },
      cache: {
        cacheLocation: 'sessionStorage',
      },
    })

    await authClient.initialize()
    const redirect = await authClient.handleRedirectPromise()
    account = redirect?.account ?? authClient.getAllAccounts()[0]
  } catch (error) {
    sessionStatus.textContent = 'Authentication configuration failed'
    appendMessage(
      'error',
      error instanceof Error ? error.message : 'Authentication configuration failed.',
    )
    return
  }

  updateSession()
  if (account) {
    void refreshUsage()
  }
}

function updateSession(): void {
  const signedIn = account !== undefined
  sessionStatus.textContent = signedIn ? 'Signed in' : 'Sign in to chat'
  signInButton.classList.toggle('hidden', signedIn)
  signOutButton.classList.toggle('hidden', !signedIn)
  usagePanel.classList.toggle('hidden', !signedIn)
  setBusy(requestBusy)
}

async function refreshUsage(): Promise<void> {
  try {
    renderUsage(await authenticatedRequest<TokenUsage>('/api/usage'))
  } catch (error) {
    usageValue.textContent = 'Usage unavailable'
    usageReset.textContent = error instanceof Error ? error.message : 'Try again later.'
  }
}

function renderUsage(usage: TokenUsage): void {
  const number = new Intl.NumberFormat()
  quotaExhausted = usage.remaining <= 0
  usageValue.textContent = `${number.format(usage.used)} of ${number.format(usage.limit)} tokens`
  const reservation = usage.reserved > 0
    ? `${number.format(usage.reserved)} reserved · `
    : ''
  usageReset.textContent = quotaExhausted
    ? `Quota exhausted · resets ${formatDate(usage.periodEnd)}`
    : `${reservation}${number.format(usage.remaining)} remaining · resets ${formatDate(usage.periodEnd)}`

  const committedAndReserved = usage.used + usage.reserved
  const percentage = usage.limit > 0
    ? Math.min(100, (committedAndReserved / usage.limit) * 100)
    : 0
  usageProgress.value = percentage
  usageProgress.textContent = `${Math.round(percentage)}%`
  usageProgress.setAttribute(
    'aria-label',
    `${number.format(usage.used)} of ${number.format(usage.limit)} monthly tokens used`,
  )
  setBusy(requestBusy)
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
  }).format(new Date(value))
}

function appendAssistantMessage(text: string, feedbackToken: string): void {
  const article = appendMessage('assistant', text)
  const controls = document.createElement('div')
  controls.className = 'feedback'
  controls.setAttribute('aria-label', 'Rate this answer')

  const helpful = feedbackButton('Helpful', '👍', 5)
  const unhelpful = feedbackButton('Not helpful', '👎', 1)
  controls.append(helpful, unhelpful)
  article.append(controls)

  function feedbackButton(label: string, glyph: string, rating: number): HTMLButtonElement {
    const button = document.createElement('button')
    button.className = 'feedback-button'
    button.type = 'button'
    button.setAttribute('aria-label', label)
    button.textContent = glyph
    button.addEventListener('click', async () => {
      helpful.disabled = true
      unhelpful.disabled = true

      try {
        await authenticatedRequest<void>('/api/feedback', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ feedbackToken, rating }),
        })
        controls.replaceChildren(document.createTextNode('Feedback recorded.'))
      } catch (error) {
        helpful.disabled = false
        unhelpful.disabled = false
        controls.append(
          document.createTextNode(
            ` ${error instanceof Error ? error.message : 'Feedback failed.'}`,
          ),
        )
      }
    })
    return button
  }
}

function appendMessage(kind: 'assistant' | 'user' | 'error', text: string): HTMLElement {
  const article = document.createElement('article')
  article.className = `message ${kind}`

  const paragraph = document.createElement('p')
  paragraph.textContent = text
  article.append(paragraph)
  messages.append(article)
  article.scrollIntoView({ behavior: 'smooth', block: 'end' })
  return article
}

function setBusy(busy: boolean): void {
  requestBusy = busy
  promptInput.disabled = busy || !account || quotaExhausted
  sendButton.disabled = busy || !account || quotaExhausted
  newChatButton.disabled = busy
  sendButton.textContent = busy ? 'Sending...' : 'Send'
}

async function authenticatedRequest<T>(url: string, init?: RequestInit): Promise<T> {
  const token = await getAccessToken()
  return requestJson<T>(url, {
    ...init,
    headers: {
      ...init?.headers,
      Authorization: `Bearer ${token}`,
    },
  })
}

async function getAccessToken(): Promise<string> {
  if (!account) {
    throw new Error('Sign in is required.')
  }

  try {
    const result = await authClient.acquireTokenSilent({
      account,
      scopes: [authScope],
    })
    return result.accessToken
  } catch (error) {
    if (error instanceof InteractionRequiredAuthError) {
      await authClient.acquireTokenRedirect({
        account,
        scopes: [authScope],
      })
    }
    throw error
  }
}

async function requestJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    headers: {
      Accept: 'application/json',
      ...init?.headers,
    },
  })

  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as ApiError
    throw new ApiRequestError(
      body.error ?? `Request failed (${response.status}).`,
      body.code,
      body.usage,
    )
  }

  if (response.status === 204) {
    return undefined as T
  }

  return (await response.json()) as T
}

function requireElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id)
  if (!element) {
    throw new Error(`Required element '${id}' was not found.`)
  }
  return element as T
}
