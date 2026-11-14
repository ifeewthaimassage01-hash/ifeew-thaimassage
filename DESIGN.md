---
name: Ifeew's Thaimassage
description: Warm cream, calm and clean design system shared by the customer booking site and the staff/owner app.
colors:
  primary: "#93704f"
  primary-hover: "#886342"
  brand-accent: "#a9825e"
  cream-canvas: "#f8f3ed"
  warm-white-surface: "#fffcf8"
  muted-fill: "#f4ebe1"
  accent-fill: "#f0e5d9"
  beige-secondary: "#ede0d2"
  border: "#ede4da"
  input-border: "#e3d6c7"
  heading: "#514337"
  body-text: "#66594d"
  secondary-text: "#7a6e61"
  muted-icon: "#b6a797"
  success: "#6f9277"
  success-ink: "#557560"
  success-soft: "#e6eee6"
  danger: "#c87870"
  danger-ink: "#9e5149"
  danger-soft: "#f6e5e1"
  pending-ink: "#72543e"
  pending-soft: "#f2e6d6"
  chart-1: "#e2c9ad"
  chart-2: "#b38b67"
  chart-3: "#6e4f37"
  chart-4: "#d9d4ce"
typography:
  display:
    fontFamily: "Cormorant Garamond, Noto Serif Thai, Georgia, serif"
    fontSize: "3.5rem"
    fontWeight: 600
    lineHeight: 1.05
  headline:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "1.75rem"
    fontWeight: 600
    lineHeight: 1.2
  title:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 600
    lineHeight: 1.4
  title-lg:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.4
  body:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.6
  small:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.4
  micro:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.25
  stat:
    fontFamily: "DM Sans, Noto Sans Thai, system-ui, sans-serif"
    fontSize: "30px"
    fontWeight: 400
    lineHeight: 1
    fontFeature: "tnum"
rounded:
  chip: "6px"
  control: "8px"
  inset: "12px"
  card: "16px"
  panel: "18px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  2xl: "24px"
  3xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#ffffff"
    rounded: "{rounded.control}"
    padding: "0 20px"
    height: "44px"
  button-primary-hover:
    backgroundColor: "{colors.primary-hover}"
  button-outline:
    backgroundColor: "{colors.warm-white-surface}"
    textColor: "{colors.heading}"
    rounded: "{rounded.control}"
    padding: "0 20px"
    height: "44px"
  button-ghost:
    textColor: "{colors.heading}"
    rounded: "{rounded.control}"
    padding: "0 12px"
    height: "36px"
  button-destructive:
    backgroundColor: "{colors.danger-ink}"
    textColor: "#ffffff"
    rounded: "{rounded.control}"
    height: "44px"
  input:
    backgroundColor: "{colors.warm-white-surface}"
    textColor: "{colors.heading}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "44px"
  card:
    backgroundColor: "{colors.warm-white-surface}"
    rounded: "{rounded.card}"
    padding: "20px"
  badge-success:
    backgroundColor: "{colors.success-soft}"
    textColor: "{colors.success-ink}"
    rounded: "{rounded.chip}"
    padding: "2px 8px"
  badge-pending:
    backgroundColor: "{colors.pending-soft}"
    textColor: "{colors.pending-ink}"
    rounded: "{rounded.chip}"
    padding: "2px 8px"
  badge-danger:
    backgroundColor: "{colors.danger-soft}"
    textColor: "{colors.danger-ink}"
    rounded: "{rounded.chip}"
    padding: "2px 8px"
  nav-item-active:
    backgroundColor: "{colors.beige-secondary}"
    textColor: "{colors.primary}"
    rounded: "{rounded.inset}"
    height: "40px"
---

# Design System: Ifeew's Thaimassage

## Overview

**Creative North Star: "The Quiet Treatment Room"**

Every screen should feel like walking into a good treatment room: warm, clean, softly lit, nothing out of place, and everything you need within reach. The cream canvas is the room; warm-white cards are the linen laid on top; muted brown is the polished teak you touch to act. Nothing shouts. Hierarchy comes from whitespace and type weight before color.

The same room serves two very different visitors. Customers on the booking site move slowly and want reassurance: a full-bleed photo, a serif wordmark, generous space, and a booking path with no surprises. Staff at the front desk move fast with a customer waiting: the same materials, but denser, with large touch targets, obvious next actions, and money always legible. Components are soft and composed at rest, then crisp and confident the moment someone has to act.

The system rejects cold gray, pure black, neon, saturated or purple-blue gradients, glassmorphism, heavy shadows, and dark brown as a large background.

**Key Characteristics:**
- One continuous cream canvas; content sits on warm-white cards with a beige hairline and a barely-there shadow.
- Muted brown is the only action color; status colors appear only with a text label.
- Thai-first typography in DM Sans + Noto Sans Thai; Cormorant Garamond only for the customer wordmark and hero.
- Tabular numbers for every price, time, count, and queue number.
- Large, forgiving controls (44px on touch, 40px on desktop).

## Colors

A warm, low-chroma cream and earth palette with one muted-brown voice and soft, labelled status tints.

### Primary
- **Teak Brown** (#93704f): primary buttons, active states, links, checked switches. White text on it passes 4.5:1. Hover deepens to **Oiled Teak** (#886342).
- **Sandalwood** (#a9825e): icons, highlights, chart lines, appointment blocks, focus ring. Graphics only, never text.

### Neutral
- **Cream Canvas** (#f8f3ed): the page, sidebar, and topbar as one continuous surface.
- **Warm Linen** (#fffcf8): cards, panels, dialogs, popovers, form fields.
- **Rice Paper** (#f4ebe1): icon circles, inset boxes, row hover.
- **Toasted Rice** (#f0e5d9): stronger hover.
- **Beige Secondary** (#ede0d2): active navigation item, selected chips, secondary buttons, preview backdrops.
- **Hairline Beige** (#ede4da): card outlines and dividers. **Input Beige** (#e3d6c7): form field outlines and unchecked switches.
- **Coffee** (#514337): headings, important numbers, primary labels.
- **Warm Ink** (#66594d): body text.
- **Driftwood** (#7a6e61): descriptions, metadata, placeholders (4.5:1 on cream).
- **Dry Reed** (#b6a797): decorative icons only.

### Status
- **Sage** success: dot/fill #6f9277, text #557560, tint #e6eee6.
- **Clay Rose** danger: dot/fill #c87870, text #9e5149, tint #f6e5e1.
- **Amber Husk** pending: text #72543e on tint #f2e6d6.

### Charts
- **Booking stage ramp** (chart-1 #e2c9ad → chart-2 #b38b67 → chart-3 #6e4f37): pending, confirmed, arrived/done, light to dark because the stages are ordered. **Warm Ash** (chart-4 #d9d4ce) for cancelled and no-show. Every segment also carries a label and count.

### Named Rules
**The 60-30-10 Rule.** Cream and warm-white make up about 60% of any screen, beige fills, borders, and text about 30%, and brown plus status colors at most 10%, only where attention is needed.

**The Graphics-Only Rule.** Sandalwood (#a9825e) and the bright status fills (#6f9277, #c87870) never carry text; text uses the matching ink (#557560, #9e5149, #72543e).

**The Never-Color-Alone Rule.** Every status shown by color also has a word or icon (badge with label, dot plus text).

## Typography

**Display Font:** Cormorant Garamond (with Noto Serif Thai, Georgia)
**Body Font:** DM Sans for Latin and numbers, Noto Sans Thai for Thai (with system-ui)

**Character:** A quiet, round sans for everything you read and operate, with a single serif moment reserved for the customer-facing wordmark and hero, the way a spa signs its door but not its menus.

### Hierarchy
- **Display** (600, ~56px on desktop, tight leading): customer hero title and the "Ifeew's Thaimassage" wordmark only.
- **Headline** (600, 24px mobile / 28px desktop, 1.2): page titles via PageHeader. Headings use Coffee and balanced wrapping.
- **Title** (600, 16px): card and section headings, dialog titles. **Title-lg** (600, 17px, `text-title`): emphasized card headings such as branch cards, POS entry cards, and setup steps.
- **Body** (400, 15px in UI, 16px document base, line-height 1.6): all running text; keep descriptions under about 68ch.
- **Small** (400, 14px, `text-sm`): secondary lines, card descriptions, chat-preview bubbles.
- **Label** (500, 13px): table headers, group labels in navigation, small metadata. Sentence case, never tracked-out capitals.
- **Micro** (400, 12px, `text-xs`): chart axis ticks, timeline hours and blocks, bottom-navigation labels only. Never for sentences.
- **Stat** (400, 26–30px, tabular): StatCard values and other large numbers.

### Named Rules
**The Tabular Money Rule.** Prices, times, dates, counts, and queue numbers use tabular figures (`.num`) so columns of money line up.

**The 13px Floor Rule.** Readable text never goes below 13px; 12px is reserved for chart ticks, timelines, and bottom-nav labels, and text is never dimmed with opacity to look secondary (use Driftwood instead).

**The One Serif Rule.** Cormorant Garamond appears only on the customer site's wordmark and hero; the staff app is sans throughout.

## Layout

- **Staff app:** cream sidebar (232px at xl, a 76px icon rail from md, hidden on mobile), compact topbar, content up to 1480px with 16px gutters on mobile and 24px from md. On mobile a fixed bottom navigation (68px plus safe area) replaces the sidebar, so the main area reserves bottom padding.
- **Customer site:** horizontal top navigation (logo, menu, LINE login, "จองคิว"), full-bleed hero with a quick booking panel on the home page, content max 1200px, minimal footer. Below 1024px the menu moves into a right-side drawer; mobile keeps a booking button within reach.
- **Rhythm:** 4px spacing scale. Sections separate with 24–40px of whitespace rather than extra borders. Settings pages use a two-column pattern on large screens: a 260px explanation column beside the form card.
- **Responsive:** single column on mobile, no horizontal page overflow, full-width primary buttons where they are the main action. Tables marked `stack` turn each row into a labelled card below 640px; the weekly schedule grid is the one table that keeps horizontal scroll, with a sticky first column. Unsaved-change bars float above the mobile bottom navigation.

## Elevation & Depth

Depth comes mostly from tonal layering (warm-white on cream, rice-paper insets on warm-white) and hairline borders. A single soft shadow lifts resting cards; stronger elevation is reserved for things that float over the page.

### Shadow Vocabulary
- **Soft** (`box-shadow: 0 4px 20px rgba(111, 83, 57, 0.055)`): resting cards, StatCards, active pill in the customer nav.
- **Float** (`box-shadow: 0 12px 32px rgba(81, 67, 55, 0.10)`): floating save bars and other overlays above content.
- **Bottom nav** (`box-shadow: 0 -6px 24px -8px rgb(74 55 40 / 0.18)`): the mobile bottom navigation only.

### Named Rules
**The Border-Before-Shadow Rule.** Prefer a hairline beige border over a shadow; never stack heavy shadows or add one to every card in a list.

## Shapes

Gently rounded and consistent by hierarchy: the bigger the container, the softer the corner. Chips and badges 6px, buttons and fields 8px, inset boxes 12px, cards 16px, large panels and chat-style previews 18px, pills and avatars fully round. Borders are 1px Hairline Beige; icon containers are circles in Rice Paper with a Sandalwood icon.

## Components

### Buttons
- **Shape:** gently rounded (8px).
- **Primary:** Teak Brown with white 15px medium text, 44px tall on touch and 40px from md; hover deepens to Oiled Teak; a slight press scale (0.98) confirms the tap.
- **Outline:** Warm Linen with Input Beige border and Coffee text; hover fills Rice Paper.
- **Ghost:** text only in Coffee, Rice Paper on hover; used for row actions and toolbars.
- **Destructive:** danger ink (#9e5149) with white text, always behind a confirmation dialog.
- **Focus:** a 3px Sandalwood ring at partial opacity on every button.

### Chips / Badges
- **Style:** 13px medium text on a soft tint (success, pending, danger, neutral, beige), 6px radius, optional leading dot in the text color.
- **Use:** booking, queue, deposit, and payment status. Always carries a word.

### Cards / Containers
- **Corner Style:** 16px (SectionCard, Card, StatCard); 18px for large grouped panels.
- **Background:** Warm Linen on Cream Canvas.
- **Shadow Strategy:** Soft shadow at rest, or none when a border already separates.
- **Border:** 1px Hairline Beige.
- **Internal Padding:** 16px on mobile, 20px from sm. SectionCard headers carry the title, description, and actions above a hairline.

### Inputs / Fields
- **Style:** Warm Linen fill, Input Beige 1px border, 8px radius, 44px tall (40px from md), Coffee text, Driftwood placeholder.
- **Focus:** border shifts to Sandalwood with a 3px soft ring.
- **Error / Disabled:** danger-ink border and faint ring; disabled at 50% opacity.
- **Labels:** always visible above the field; hints in 13px Driftwood below.

### Navigation
- **Staff sidebar:** grouped links with 13px group labels; items 40px tall, 12px radius; active item in Beige Secondary with a Teak Brown icon; hover Rice Paper.
- **Staff mobile:** fixed bottom bar with five destinations, rounded top corners, warm-white surface.
- **Customer:** pill links in the topbar, the active one on Warm Linen with the Soft shadow; drawer on small screens.

### Status Stepper (signature)
Setup flows (LINE OA) use one panel with numbered steps divided by hairlines: done steps collapse to a sage check and one-line summary, the next step stays open with a Teak Brown number, locked steps show a lock in muted tones.

### Message Preview (signature)
Where the product sends messages (LINE), a chat-style preview sits on Beige Secondary with warm-white bubbles (18px, flattened top-left corner) so the owner sees exactly what customers and staff will read.

## Do's and Don'ts

### Do:
- **Do** keep the canvas Cream Canvas (#f8f3ed) everywhere and put content on Warm Linen (#fffcf8) cards with a Hairline Beige border.
- **Do** use Teak Brown (#93704f) only for the primary action on a view and for active/selected states.
- **Do** pair every status color with a label, and use the ink shade (#557560, #9e5149, #72543e) for status text.
- **Do** use tabular figures for all money, time, and counts.
- **Do** keep touch targets at least 40px (44px for primary actions on touch screens) and respect reduced motion.
- **Do** show clear confirmation dialogs, with a reason field, for destructive or money-moving actions.

### Don't:
- **Don't** use dark brown as a large background, pure black, cold gray, neon, or purple/blue gradients.
- **Don't** add heavy shadows, glassmorphism, or borders between sidebar, topbar, and content.
- **Don't** use Sandalwood (#a9825e) or the bright status fills as text color.
- **Don't** use the serif display face inside the staff app.
- **Don't** use all-caps or tracked-out labels.
- **Don't** let content overflow horizontally on mobile; stack tables instead of forcing sideways scroll.
