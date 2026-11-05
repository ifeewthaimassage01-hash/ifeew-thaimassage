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

Use a warm cream and earthy neutral color palette as the primary visual identity.

The overall interface must be cream-dominant, with soft beige, natural sand, and muted brown tones used to create visual hierarchy.

| Token | Color | Usage |
|---|---|---|
| Primary | #8A6A50 | Primary buttons, active states |
| Primary Hover | #72543E | Button hover, interactive states |
| Accent | #B38B67 | Highlights, secondary emphasis |
| Background | #F7F3EB | Main application background |
| Surface | #FFFEFC | Cards, panels, content areas |
| Secondary Surface | #EAE0D1 | Secondary sections, subtle backgrounds |
| Border | #E8DFD4 | Borders, dividers, separators |
| Heading | #514337 | Page titles, important headings |
| Text | #66594D | Primary body text |
| Muted | #A39789 | Secondary text, placeholders |
| Success | #6F9277 | Success states, completed bookings |
| Danger | #C87870 | Errors, warnings, destructive actions |

### Color Rules

- Use Background (#F7F3EB) as the dominant background color throughout the application.
- Use Surface (#FFFEFC) for cards, panels, tables, forms, and content containers.
- Use Primary (#8A6A50) for important buttons, active navigation items, and primary actions.
- Use Primary Hover (#72543E) for hover and pressed states.
- Use Accent (#B38B67) sparingly for highlights, icons, and secondary emphasis.
- Use Secondary Surface (#EAE0D1) for subtle section backgrounds and secondary UI elements.
- Use Heading (#514337) for headings and important labels.
- Use Text (#66594D) for primary body text.
- Use Muted (#A39789) for descriptions, metadata, and secondary information.
- Use Border (#E8DFD4) for subtle separators and component outlines.
- Use Success and Danger only for meaningful status indicators.

### Visual Color Balance

- 60% Warm Cream and Background
- 25% White and Surface
- 10% Brown and Primary
- 5% Accent and Status Colors

### Important Restrictions

- Cream must remain the dominant color.
- Do not use dark brown as a large background color.
- Avoid pure black backgrounds.
- Avoid cold gray, neon colors, and overly saturated colors.
- Avoid excessive gradients and colorful decorations.
- Do not make every card use a different background color.
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

The final result should look like a premium, minimal SaaS dashboard similar in layout quality to the reference image, but with a warm cream and earthy neutral visual identity.

The interface must feel:

- Minimal, not empty.
- Premium, not luxurious or excessive.
- Professional, not overly corporate.
- Warm, calm, and welcoming.
- Simple, not generic.
- Consistent across Customer and Staff/Owner interfaces.

Use cream as the dominant visual foundation, white as the primary content surface, and muted brown as the main interactive color.

Prioritize visual hierarchy, whitespace, usability, consistency, and accessibility over decorative effects.

The final UI should resemble a premium boutique wellness and massage platform rather than a generic corporate dashboard.