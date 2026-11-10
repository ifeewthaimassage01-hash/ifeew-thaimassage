# UI Design Prompt — Minimal Premium Dashboard

Act as a Senior UI/UX Designer and Frontend Developer.

Design and build a modern, minimal, premium SaaS web application inspired by the provided reference image.

The design should feel clean, elegant, professional, lightweight, and easy to use. Avoid unnecessary visual elements, excessive shadows, gradients, and decorative components.

## 1. Design Direction

- Style: Minimal SaaS Dashboard
- Visual direction: Clean, Modern, Premium, Elegant
- Layout: Sidebar + Top Navigation + Main Content
- UI density: Comfortable spacing with generous whitespace
- Components: Simple cards, subtle borders, clean typography
- Border radius: 8–12px
- Shadows: Very subtle or none
- Icons: Simple consistent line icons
- Typography: Modern sans-serif, highly readable

Use the provided reference image as a layout and visual inspiration, not as something to copy pixel by pixel.

## 2. Color Design System

Use a warm cream and ivory palette with muted brown accents (Warm Cream Minimal Dashboard). The canvas is cream, content floats on warm-white cards with subtle beige borders and soft diffused shadows.

| Token | Color | Usage |
|---|---|---|
| Background | #F8F3ED | Page canvas, sidebar, topbar (one continuous cream surface, no dividers) |
| Surface | #FFFCF8 | Cards, panels, dialogs, form fields |
| Muted Fill (Surface Secondary) | #F4EBE1 | Icon circles, inset boxes, hover states |
| Accent Fill | #F0E5D9 | Stronger hover |
| Secondary | #EDE0D2 | Active navigation item, badges, secondary buttons |
| Border | #EDE4DA | Card outlines, dividers |
| Input Border | #E3D6C7 | Form field outlines |
| Primary | #93704F | Primary buttons, active states (white text passes 4.5:1) |
| Primary Dark | #886342 | Button hover, pressed states |
| Brand Accent | #A9825E | Icons, highlights, appointment blocks, chart lines (not for text) |
| Heading | #514337 | Page titles, important headings, numbers |
| Text | #66594D | Body text |
| Secondary Text | #7A6E61 | Descriptions, metadata (4.5:1 on cream) |
| Muted Icon | #B6A797 | Decorative icons only |
| Success / Danger | #6F9277 / #C87870 | Status dots and pills only, always with a label |

Shadow: `0 4px 20px rgba(111, 83, 57, 0.055)` (`shadow-soft`). Radius: cards 16px, inset boxes 12px, buttons and fields 8px, chips 6px.

Typography: DM Sans for Latin and numbers, Noto Sans Thai for Thai. Display headings and the wordmark on the customer site use Cormorant Garamond (`font-display`). Large numbers use 30px regular.

### Color Rules

- Keep the canvas cream (#F8F3ED) everywhere; do not add borders between sidebar, topbar and content.
- Put content on Surface cards (#FFFCF8) with Border (#EDE4DA) and the soft shadow, never heavy shadows.
- Use small circular icon containers in Muted Fill (#F5EDE4) with Brand Accent icons.
- Use Secondary (#EDE0D2) for the active navigation item and selected states.
- Use Primary (#93704F) only for primary actions; Brand Accent (#A9825E) is for graphics, never text.
- Use Success and Danger only for meaningful status indicators, with a text label.

### Visual Color Balance (60-30-10)

- **60% — Dominant:** Cream canvas (#F8F3ED) and warm-white cards (#FFFCF8).
- **30% — Secondary (Structure):** Muted Fill, Secondary beige, borders, and text colors.
- **10% — Accent:** Primary/Brand Accent brown and status colors, only where attention is needed.

### Important Restrictions

- Do not use dark brown as a large background color.
- Avoid pure black backgrounds, cold gray, neon, purple/blue gradients and saturated colors.
- Avoid heavy shadows, excessive borders and glassmorphism.
- Maintain sufficient contrast and accessibility.
- Keep the overall interface warm, calm, natural, and visually consistent.

## 3. Layout Structure

### Desktop

- Fixed or sticky sidebar on the left.
- Compact top navigation bar.
- Main content area with a clear page heading.
- Use a responsive grid for dashboard cards.
- Keep consistent margins and spacing.
- Footer should be minimal.

### Sidebar

- Brand logo and application name.
- Simple navigation menu with line icons.
- Clearly distinguish the active menu item.
- Use a subtle background or border.
- Avoid oversized navigation elements.

### Top Navigation

- Page context or breadcrumb.
- Account/profile information.
- Notifications when relevant.
- Primary action button.
- Keep the navigation compact.

### Main Content

- Clear page title and optional description.
- Summary cards for important information.
- Content sections separated by whitespace.
- Tables with clean headers and subtle dividers.
- Empty states with simple illustrations and clear actions.

## 4. Customer Interface

Layout: horizontal top navigation (logo · menu · จองคิว · account), full-bleed hero with photo and quick booking panel on the home page, content max width 1200px, footer. Mobile uses a menu drawer and a sticky booking button.

Create a dedicated customer experience.

Focus on:

- Finding massage services.
- Browsing service details.
- Viewing available schedules.
- Booking appointments.
- Managing reservations.
- Viewing booking history.
- Managing personal profile.

Customer interface should prioritize simplicity and ease of booking.

Do not expose internal shop management functions to customers.

## 5. Staff / Shop Owner Interface

Create a separate management experience.

Focus on:

- Overview dashboard.
- Appointment management.
- Calendar and booking schedules.
- Customer management.
- Massage service management.
- Staff management.
- Revenue and sales reports.
- Shop settings.

Staff and shop owners should have access only to functions allowed by their roles.

## 6. Responsive Design

Desktop:

- Full sidebar.
- Multi-column dashboard layout.
- Tables with comfortable spacing.

Tablet:

- Compact sidebar.
- Flexible card grid.
- Optimized content width.

Mobile:

- Replace sidebar with a compact navigation menu or drawer.
- Single-column content.
- Full-width primary buttons when appropriate.
- Touch-friendly controls.
- No horizontal overflow.
- Keep important actions easily accessible.

## 7. Component Design

Create reusable components:

- Button
- Input
- Select
- Card
- Badge
- Modal
- Dropdown
- Sidebar
- Topbar
- Data Table
- Empty State
- Loading State
- Toast Notification

All components must follow the same design tokens and visual rules.

## 8. Interaction & UX

- Clear hover and active states.
- Smooth but subtle transitions.
- Consistent form validation.
- Clear confirmation for destructive actions.
- Meaningful loading and empty states.
- Avoid unnecessary animations.
- Prioritize accessibility and usability.

## 9. Development Requirements

- Use clean, maintainable code.
- Use reusable components and consistent naming.
- Separate Customer and Staff/Owner interfaces into two independent files.
- Maintain consistent design tokens across both interfaces.
- Avoid duplicated styling.
- Ensure responsive behavior at all screen sizes.
- Use semantic HTML and accessible interactions.

## 10. Final Design Goal

The final result should look like a premium, minimal SaaS dashboard similar in layout quality to the reference image, with a warm cream and earthy neutral visual identity.

The interface must feel:

- Minimal, not empty.
- Premium, not luxurious or excessive.
- Professional, not overly corporate.
- Warm, calm, and welcoming.
- Simple, not generic.
- Consistent across Customer and Staff/Owner interfaces.

Follow the 60-30-10 rule: cream canvas and warm-white cards as the dominant foundation (60%), beige fills, borders, and text as the structural layer (30%), and muted brown as the accent and main interactive color (10%).

Prioritize visual hierarchy, whitespace, usability, consistency, and accessibility over decorative effects.

The final UI should resemble a premium boutique wellness and massage platform rather than a generic corporate dashboard.