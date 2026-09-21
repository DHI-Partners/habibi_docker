# Habibi Burger → ideal customer & launch campaign

Status: draft for review · 2026-09-22
Inputs: `burger-role-playbook.html` (Parts 0–8), `burger-shakedown-run.html`,
the habibi_ai Telegram agent (@chooseRightWay, full order intake live),
`site-habibi/src/components/Pricing.tsx`.

Decisions already made:

- **Markets:** CIS and Gulf. Kazakhstan and Saudi Arabia go first.
- **Offer:** a done-for-you setup at a fixed price, then a monthly SaaS subscription.
- **Positioning:** food delivery is the beachhead. Other shops that sell through chat come in wave 2.

Numbers marked *(est.)* are planning assumptions, not measured data. Validate
them in the first 20 discovery calls.

---

## 1. One-line positioning

> **Your orders come in through chat. Habibi turns every message into a paid,
> cooked, delivered and booked order. The AI takes the order at 23:40 while you sleep.**

Category words the customer uses: *бот для приёма заказов, CRM для доставки,
учёт доставки еды* / *نظام طلبات واتساب, برنامج إدارة مطبخ سحابي*.
We don't lead with "ERP". The word is scary at this size. We mention ERP once, as the proof: "a full accounting system underneath".

---

## 2. Ideal customer profile — shared core

**"Chat-first delivery kitchen":** a food business where at least 40% of orders
arrive through Telegram, WhatsApp or Instagram DMs, rather than through aggregators or walk-in customers.

| Attribute | Ideal | Acceptable |
|---|---|---|
| Staff | 4–12 | 1–20 |
| Team shape | owner + 1–2 order-takers + 2–6 kitchen + 1–4 own couriers | owner does orders, couriers are Yandex/Glovo |
| Locations | 1–2 kitchens | up to 3 |
| Orders/day | 60–200 | 30–300 |
| Own-channel share | ≥ 60% DM / phone | ≥ 40% |
| Current tools | WhatsApp Business + notebook / Google Sheets | Poster, or a Tilda/Taplink site with a form |
| Age of business | 1–5 years, past survival, growing | 6 months+ |

**Formats, best first:**

1. Burger, shawarma, doner and pizza delivery.
2. Sushi and rolls.
3. Dark or cloud kitchens running 1–3 brands.
4. Healthy-food and meal-box subscriptions, which repeat daily and suit the AI well.
5. Home bakers and cake makers who have become a brand.
6. Plov and national-cuisine delivery.

**The buyer:** the owner-operator, aged 25–45. They run Instagram themselves and are on their phone all day. They decide alone and pay by card. Often a former hired manager or a second-generation family business. They don't read spec sheets; they watch a 60-second clip, then DM.

**Their pains, most acute first:**

1. DMs get lost or answered late at peak time and at night. Each missed message is a lost ₸6–8k / SAR 60.
2. Order-takers cost a salary and still make mistakes: wrong address, wrong item, forgotten sauce.
3. Food gets cooked and never paid for (cash no-shows, "I'll pay the courier" customers).
4. Couriers are chaotic, and "where is my order?" calls tie up the kitchen phone.
5. No customer base. The 1,000 people who ordered are scattered across chats and can't be re-marketed to.
6. Aggregators take a 20–35% commission and own the customer. The owner wants those customers on their own channel.
7. The owner can't see today's revenue without calling someone.

**Buying triggers**, which are also good ad-timing signals:

- About to hire a second or third order-taker.
- Opening a second point or second brand.
- An aggregator raises its fees or delists them.
- A peak season is coming: New Year and Nauryz in the CIS; Ramadan, Eid and National Day in the Gulf.
- A 1-star review about a lost or late order.
- The accountant asks for proper VAT records.

**Disqualify (don't spend ad money on these):**

- Dine-in restaurants already running iiko or r_keeper with a full POS.
- Businesses with more than 50 staff, or more than 5 points. These are enterprise sales, not this campaign.
- Businesses selling only through aggregators, with no own channel.
- Anyone who needs stock control and recipe costing on day one. It's out of scope for the current build, so offer it as phase 2.

---

## 3. Regional variants

| | **CIS** (KZ → UZ/KG → RU) | **Gulf** (KSA → UAE) |
|---|---|---|
| First cities | Almaty, Astana, Shymkent, then Tashkent | Riyadh, Jeddah, Dammam, then Dubai |
| Average check *(est.)* | ₸4–8k (~$8–16) | SAR 40–90 (~$11–24) |
| Revenue per month *(est.)* | $15k–100k | $30k–200k |
| Net margin *(est.)* | 8–15% | 10–18% |
| Order channels | Telegram, WhatsApp, Instagram | WhatsApp, Instagram, Snapchat |
| Payments | Kaspi Pay (dominant), card, cash | Mada, Apple Pay, STC Pay, Tabby, cash |
| Aggregators to position against | Wolt, Glovo, Yandex Eda | HungerStation, Jahez, Talabat, Keeta |
| Labour the AI replaces *(est.)* | 1 order-taker shift ≈ $300–500/month | 1 expat order-taker ≈ $800–1,500/month |
| Language | Russian (Kazakh and Uzbek subtitles later) | Arabic first, English second |
| Tax / compliance | 12% VAT in KZ, already modelled in the demo | 15% VAT + ZATCA e-invoicing (Phase 2 integration). Have a clear answer before selling in KSA. |
| Price sensitivity | High. Lead with the ROI math. | Medium. Lead with reliability and brand. |

**Wave 2 in both regions:** use the same footage with a different hook. Targets are flower shops, custom cakes and bakeries, and cosmetics or clothing shops selling on Instagram. They all run the same loop: DM → order → prepayment → courier. Launch this only after the food campaign has 3 or more paying customers to use as cases.

---

## 4. Offer

**Setup:** a fixed price, live in 1–2 weeks. Included:

- Menu and price import.
- Customer-base import, which turns their chat history into a customer list.
- AI agent connected to their channel.
- Order workflow with the prepayment gate.
- Kitchen tablet board.
- Courier roles and the owner dashboard.
- One training session per seat.

Proposed setup prices *(to validate)*: CIS $400–800, Gulf $1,000–2,500.

**Subscription:** priced per company in €, according to the current price list.

- **Habibi Pro, €49/month:** up to 50 users, with integrations. This is the default, because the AI bot is an integration.
- **Habibi Premium, €199/month:** multi-brand, 2 or more points, managed support.
- **Habibi, €19/month:** does not cover the AI agent, so don't advertise it in this campaign.
- ⚠ **Decide:** is the AI agent included in Pro, or billed as an add-on per conversation? LLM costs scale with order volume.

**Risk reversal:** a 14-day pilot on their real menu. They pay for setup only when they go live.

**ROI math for the video and the sales call (CIS example):**

> An order-taker for the night shift costs about ₸200k a month.
> Habibi Pro plus the AI costs about ₸30k a month.
> Even at one extra order a night that used to be lost (₸6.7k × 30 = ₸200k), it pays for itself in the first month.
> And every direct order you win back from an aggregator saves you about 25%.

---

## 5. YouTube hero video: "One burger, from chat to accounts"

8–12 minutes. Russian master for the CIS; Arabic voiceover or AR/EN subtitles for the Gulf.
It follows the playbook's single order (Aigerim, burger + fries + lemonade, ₸6,670) from start to finish.

| Time | Scene | Playbook source | On screen |
|---|---|---|---|
| 0:00–0:30 | **Cold open.** It's 23:40 and the owner is asleep. A customer writes to @chooseRightWay. The AI asks what's missing, reads back the quote (priced by the ERP, VAT included), warns it will be delivered when the kitchen opens, and gets "yes". | Part 1 Intake | Phone screen-record of the chat, then cut to the new order appearing in the ERP |
| 0:30–1:30 | **The problem.** 40 unread DMs, a notebook, a cooked order nobody paid for, a courier calling. | — | B-roll or staged shots |
| 1:30–2:30 | **Three seats, one system.** Order desk, kitchen tablet, courier. Each seat sees only what it needs. | Part 0 Cast | Three browser windows side by side |
| 2:30–3:30 | **What the AI did.** Found the customer by phone, took prices from the ERP (never from memory), created the order. A human can still fix it while it's a draft. | Part 1 Intake | The Sales Order form |
| 3:30–5:00 | **No money, no cooking.** Confirm the order, try to send it to the kitchen, and the system refuses. Record the Kaspi payment, and the "send to kitchen" action appears. | Part 2 Money | **Hero moment.** Show the refusal clearly. |
| 5:00–6:00 | **The pass.** A Kanban on the tablet. Read the ticket without opening it, drag it to Ready. Show that the kitchen seat can't touch the price. | Part 3 Kitchen | Tablet |
| 6:00–7:00 | **Dispatch and courier.** Assign a courier, print the delivery note. The courier sees only their own runs and closes the delivery. | Parts 4–5 | Phone view as the courier |
| 7:00–7:45 | **Books close themselves.** Invoice raised from the order, VAT split checked. Cancelling costs nothing extra. | Part 6 Books | Invoice |
| 7:45–8:30 | **When the AI hands it back.** The operator sees the whole chat in the Telegram Chat Console, replies by hand, and the bot steps aside in that chat alone. | Part 7 Escalation | Telegram Chat Console |
| 8:30–9:30 | **The owner's dashboard.** Today's orders, revenue, split by channel. Checked against the board. | Part 8 Analysis | Dashboard |
| 9:30–10:30 | **The money.** The ROI math from section 4, plus the aggregator comparison. | — | Simple animated numbers |
| 10:30–end | **Call to action.** 1) "Order a burger from our bot yourself" (link to @chooseRightWay). 2) "Book a free 20-minute order-flow audit". | — | QR code + link |

**Five cut-downs, 45–60 seconds each, for Shorts, Reels and TikTok.** One pain per clip:

1. "The AI took an order at 23:40."
2. "The system won't let the kitchen cook until the order is paid."
3. "A courier who can't lose the address."
4. "The owner's day in one screen."
5. "Order-taker vs AI: the math."

Every clip ends with "Order from the bot yourself."

**Before recording:**

- Get written OK from the Habibi Burger client to show their brand and data. If they say no, re-skin it as a "Demo Burger" company.
- Use only demo customers. Blur phone numbers.
- Confirm the bot is stable for the public. People from the ads will actually order through it, so it needs a demo mode that doesn't dispatch a real courier.
- **Gulf cut:** Gulf customers live on WhatsApp, but the demo uses Telegram, and `habibi_whatsapp` isn't configured yet (Meta Business Verification hasn't started). Either get WhatsApp working before the Gulf launch, or say honestly "same agent, your channel: Telegram today, WhatsApp on go-live".

---

## 6. Ad and outreach copy drafts

**RU — hook variants:**

- «Заказ в 23:40. Вы спите. Бот уже принял его, проверил цену и отправил на кухню — после оплаты.»
- «Сколько заказов вы потеряли в директе на этой неделе?»
- «Кухня не начнёт готовить, пока заказ не оплачен. Не по правилам — по системе.»
- «Оператор ночной смены: ₸200 000. Бот: меньше ₸30 000.»

**RU — outbound DM** (to Instagram accounts that take orders in direct):
> Здравствуйте! Видел, что вы принимаете заказы в директе/WhatsApp. Сделали
> для доставки бота, который сам принимает заказ, проверяет оплату и ведёт
> его до курьера и бухгалтерии. Вот 60 секунд, как это выглядит: [ссылка].
> Можно заказать тестовый бургер у бота самому — интересно ваше мнение.

**AR — hook variants:**

- «طلب الساعة 11:40 مساءً وأنت نائم. الوكيل الذكي استلمه وأكّد السعر وأرسله للمطبخ بعد الدفع.»
- «كم طلب ضاع في الواتساب هذا الأسبوع؟»
- «بدل موظف استقبال الطلبات: وكيل ذكي يعمل ٢٤ ساعة بالعربي والإنجليزي.»

**EN — hook variants:**

- "Your kitchen takes orders in DMs. Ours takes them at midnight, checks payment, and books the VAT."
- "Stop paying 30% to aggregators for customers who already DM you."

---

## 7. Distribution and funnel

**The funnel:** video or clip → a food-delivery landing page on site-habibi (RU / AR / EN) → **the prospect orders a burger from the bot** (the "aha" moment) → they book a 20-minute audit → a 14-day pilot → setup is paid → subscription.

| Channel | CIS | Gulf |
|---|---|---|
| Paid social | Instagram and Facebook Reels (KZ, UZ), with interest targeting on restaurant and food-business owners | Instagram, **Snapchat** (strong in KSA), TikTok |
| Search | Google and Yandex: «бот для приема заказов», «программа для доставки еды» | Google in Arabic: «نظام طلبات واتساب للمطاعم» |
| Telegram | Telegram Ads, restaurant-owner chats and channels, a guest post on a HoReCa channel | — |
| Outbound | Build a list from 2GIS (category "доставка еды") plus Instagram hashtags (#доставкаалматы, #бургерыалматы). DM each one the 60-second clip. | Instagram home kitchens and cloud-kitchen operators; LinkedIn for multi-brand operators |
| Partners | Packaging suppliers, meat and bun suppliers, restaurant accountants | Cloud-kitchen facilities (which host 10–30 brands each), and Tabby/Mada merchant programmes |
| YouTube | The hero video, with titles optimised for search: «Как автоматизировать доставку еды» | An Arabic version titled "أتمتة مطعم التوصيل" |

**Four-week test budget *(est.)*:** $1.5–3k per region. That's 3 hooks × 2 audiences, then scale the winner.

**KPIs:**

| Metric | CIS target | Gulf target |
|---|---|---|
| Cost per completed bot demo | < $5 | < $12 |
| Cost per booked audit | < $25 | < $60 |
| Audit → pilot | ≥ 30% | ≥ 30% |
| Pilot → paid | ≥ 50% | ≥ 50% |
| First 10 paying customers | 8 weeks | 12 weeks |

**Outbound volume:** 50 personalised DMs a day per region, aiming for a 5% reply rate and 1 audit a day.

---

## 8. Sample personas (for creative briefs)

- **Aidos, 32, Almaty.** Runs "Smash & Go", a burger delivery. 8 staff and 110 orders a day, 70% of them from Instagram and WhatsApp. He has two order-takers and is about to hire a third for the night shift. Glovo takes 30% of the rest. He was burned by an iiko quote once ("too big for us"). He watches YouTube in Russian. Buys if it's live before New Year.
- **Nour, 29, Riyadh.** Runs a home-kitchen brand that turned into a cloud kitchen, selling mandi and burgers. 12 staff and 150 orders a day, split between WhatsApp and HungerStation. Her order-takers are expats who struggle with the Arabic-speaking customers. She needs ZATCA-proper invoices. Buys before Ramadan.
- **Dilnoza, 38, Tashkent.** Runs a meal-box subscription with 5 staff and 60 recurring orders a day in Telegram. She loses track of pauses and address changes, and the AI plus the customer base is the whole value for her. Price-sensitive; will start on Pro.

---

## 9. Open items before launch

1. **Pricing:** is the AI included in Pro or billed separately? Confirm the setup fees for each region.
2. **Rights:** permission to show the Habibi Burger brand on camera, or re-skin it.
3. **Public demo mode for the bot:** a separate demo company, so orders from ad traffic never reach a real kitchen.
4. **Gulf readiness:** get WhatsApp working (Meta verification), an Arabic-language agent, and a ZATCA e-invoicing answer.
5. **Landing page:** a food-delivery vertical page on site-habibi in RU, AR and EN, with the bot link and audit booking.
6. **Discovery calls:** 20 calls, 10 per region, to validate the *(est.)* numbers before scaling the ad spend.
