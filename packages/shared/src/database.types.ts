// =============================================================================
// Supabase Database types — Phase 1
// -----------------------------------------------------------------------------
// ไฟล์นี้เขียนตาม migrations ใน supabase/migrations (รูปแบบเดียวกับ supabase gen types)
// เมื่อมี local stack / dev project แล้วให้สร้างทับด้วย:  pnpm db:types
// =============================================================================

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

type Stamp = {
  created_at: string
  created_by: string | null
  updated_at: string
}

type StampInsert = {
  created_at?: string
  created_by?: string | null
  updated_at?: string
}

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: Stamp & {
          id: string
          display_name: string
          phone: string | null
          avatar_path: string | null
        }
        Insert: StampInsert & {
          id: string
          display_name?: string
          phone?: string | null
          avatar_path?: string | null
        }
        Update: {
          display_name?: string
          phone?: string | null
          avatar_path?: string | null
        }
        Relationships: []
      }
      companies: {
        Row: Stamp & {
          id: string
          code: string
          name: string
          legal_name: string | null
          tax_id: string | null
          is_active: boolean
        }
        Insert: StampInsert & {
          id?: string
          code: string
          name: string
          legal_name?: string | null
          tax_id?: string | null
          is_active?: boolean
        }
        Update: {
          name?: string
          legal_name?: string | null
          tax_id?: string | null
        }
        Relationships: []
      }
      company_settings: {
        Row: Stamp & {
          attendance_grace_minutes: number
          max_staff_discount_percent: number
          company_id: string
          timezone: string
          cancellation_cutoff_hours: number
          large_expense_threshold: number
          staff_pin_max_attempts: number
          staff_pin_lockout_minutes: number
          staff_idle_lock_minutes: number
          booking_slot_minutes: number
          booking_buffer_minutes: number
          booking_hold_minutes: number
          booking_max_advance_days: number
          booking_min_lead_minutes: number
          booking_max_items: number
          deposit_per_person: number
          guest_max_active_bookings: number
          tracking_token_days_after: number
          no_show_grace_minutes: number
        }
        Insert: StampInsert & {
          company_id: string
          timezone?: string
          cancellation_cutoff_hours?: number
          large_expense_threshold?: number
          staff_pin_max_attempts?: number
          staff_pin_lockout_minutes?: number
          staff_idle_lock_minutes?: number
        }
        Update: {
          cancellation_cutoff_hours?: number
          large_expense_threshold?: number
          staff_pin_max_attempts?: number
          staff_pin_lockout_minutes?: number
          staff_idle_lock_minutes?: number
          booking_slot_minutes?: number
          booking_buffer_minutes?: number
          booking_hold_minutes?: number
          booking_max_advance_days?: number
          booking_min_lead_minutes?: number
          booking_max_items?: number
          deposit_per_person?: number
          guest_max_active_bookings?: number
          tracking_token_days_after?: number
          no_show_grace_minutes?: number
        }
        Relationships: []
      }
      branches: {
        Row: Stamp & {
          default_daily_guarantee: number | null
          id: string
          company_id: string
          code: string
          name: string
          address: string | null
          phone: string | null
          map_url: string | null
          is_active: boolean
          sort_order: number
        }
        Insert: {
          company_id: string
          code: string
          name: string
          address?: string | null
          phone?: string | null
          map_url?: string | null
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          name?: string
          address?: string | null
          phone?: string | null
          map_url?: string | null
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      company_memberships: {
        Row: Stamp & {
          id: string
          company_id: string
          user_id: string
          role: 'OWNER' | 'STAFF'
          status: 'ACTIVE' | 'SUSPENDED' | 'REVOKED'
          effective_from: string
          effective_to: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      branch_memberships: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          user_id: string
          status: 'ACTIVE' | 'REVOKED'
          effective_from: string
          effective_to: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      audit_logs: {
        Row: {
          id: string
          company_id: string | null
          branch_id: string | null
          actor_user_id: string | null
          action: string
          table_name: string | null
          record_id: string | null
          old_values: Json | null
          new_values: Json | null
          reason: string | null
          metadata: Json
          occurred_at: string
          created_at: string
          created_by: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      document_sequences: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          doc_type: string
          period_key: string
          last_number: number
        }
        Insert: never
        Update: never
        Relationships: []
      }
      branch_devices: {
        Row: {
          id: string
          company_id: string
          branch_id: string
          name: string
          status: 'ACTIVE' | 'REVOKED'
          paired_by: string
          paired_at: string
          last_seen_at: string | null
          revoked_by: string | null
          revoked_at: string | null
          revoke_reason: string | null
          created_at: string
          updated_at: string
        }
        Insert: never
        Update: never
        Relationships: []
      }
      branch_opening_hours: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          iso_dow: number
          is_closed: boolean
          opens_at: string | null
          closes_at: string | null
        }
        Insert: never
        Update: {
          is_closed?: boolean
          opens_at?: string | null
          closes_at?: string | null
        }
        Relationships: []
      }
      branch_holidays: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          holiday_date: string
          name: string
          is_closed: boolean
          opens_at: string | null
          closes_at: string | null
          is_active: boolean
        }
        Insert: {
          company_id: string
          branch_id: string
          holiday_date: string
          name: string
          is_closed?: boolean
          opens_at?: string | null
          closes_at?: string | null
        }
        Update: {
          name?: string
          is_closed?: boolean
          opens_at?: string | null
          closes_at?: string | null
          is_active?: boolean
        }
        Relationships: []
      }
      employees: {
        Row: Stamp & {
          employment_type: 'REGULAR' | 'FREELANCE'
          id: string
          company_id: string
          user_id: string
          employee_code: string
          nickname: string
          photo_path: string | null
          start_date: string
          status: 'ACTIVE' | 'INACTIVE' | 'RESIGNED'
          status_changed_at: string
          resigned_at: string | null
        }
        Insert: never
        Update: {
          employee_code?: string
          nickname?: string
          photo_path?: string | null
          start_date?: string
          employment_type?: 'REGULAR' | 'FREELANCE'
        }
        Relationships: []
      }
      employee_transfers: {
        Row: Stamp & {
          id: string
          company_id: string
          employee_id: string
          from_branch_id: string | null
          to_branch_id: string
          from_membership_id: string | null
          to_membership_id: string
          effective_from: string
          reason: string
          status: 'ACTIVE' | 'CANCELLED'
          cancelled_at: string | null
          cancelled_by: string | null
          cancel_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      employee_schedules: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          employee_id: string
          starts_at: string
          ends_at: string
          status: 'SCHEDULED' | 'LEAVE' | 'CANCELLED'
          note: string | null
        }
        Insert: {
          company_id: string
          branch_id: string
          employee_id: string
          starts_at: string
          ends_at: string
          note?: string | null
        }
        Update: {
          starts_at?: string
          ends_at?: string
          status?: 'SCHEDULED' | 'LEAVE' | 'CANCELLED'
          note?: string | null
        }
        Relationships: []
      }
      service_categories: {
        Row: Stamp & {
          id: string
          company_id: string
          name: string
          description: string | null
          sort_order: number
          is_active: boolean
        }
        Insert: { company_id: string; name: string; description?: string | null; sort_order?: number }
        Update: { name?: string; description?: string | null; sort_order?: number; is_active?: boolean }
        Relationships: []
      }
      services: {
        Row: Stamp & {
          id: string
          company_id: string
          category_id: string
          name: string
          name_en: string | null
          description: string | null
          image_path: string | null
          sort_order: number
          is_active: boolean
        }
        Insert: {
          company_id: string
          category_id: string
          name: string
          name_en?: string | null
          description?: string | null
          sort_order?: number
        }
        Update: {
          category_id?: string
          name?: string
          name_en?: string | null
          description?: string | null
          image_path?: string | null
          sort_order?: number
          is_active?: boolean
        }
        Relationships: []
      }
      branch_services: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          service_id: string
          is_active: boolean
          sort_order: number
        }
        Insert: never
        Update: { is_active?: boolean; sort_order?: number }
        Relationships: []
      }
      branch_service_options: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_service_id: string
          duration_minutes: number
          is_active: boolean
        }
        Insert: never
        Update: never
        Relationships: []
      }
      service_price_histories: {
        // therapist_fee ไม่ได้ grant ให้ client (OWNER อ่านผ่าน owner_service_pricing)
        Row: Stamp & {
          id: string
          company_id: string
          branch_service_option_id: string
          price: number
          effective_from: string
          effective_to: string | null
          status: 'ACTIVE' | 'CANCELLED'
          reason: string
          cancelled_at: string | null
          cancelled_by: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      customers: {
        Row: Stamp & {
          id: string
          company_id: string
          auth_user_id: string | null
          first_name: string
          last_name: string
          phone: string | null
          email: string | null
          staff_note: string | null
          created_channel: 'ONLINE' | 'STAFF'
          status: 'ACTIVE' | 'MERGED' | 'ANONYMIZED'
          merged_into_id: string | null
          merged_at: string | null
          anonymized_at: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      privacy_policy_versions: {
        Row: Stamp & {
          id: string
          company_id: string
          policy_type: 'PRIVACY_NOTICE' | 'MARKETING'
          version: string
          title: string
          content: string
          published_at: string
        }
        Insert: {
          company_id: string
          policy_type: 'PRIVACY_NOTICE' | 'MARKETING'
          version: string
          title: string
          content: string
          published_at?: string
        }
        Update: never
        Relationships: []
      }
      customer_consents: {
        Row: Stamp & {
          id: string
          company_id: string
          customer_id: string
          policy_version_id: string
          consent_type: 'PRIVACY_NOTICE' | 'MARKETING'
          granted: boolean
          channel: 'ONLINE' | 'STAFF'
          recorded_at: string
        }
        Insert: never
        Update: never
        Relationships: []
      }
      customer_data_requests: {
        Row: Stamp & {
          id: string
          company_id: string
          customer_id: string
          request_type: 'DELETE'
          status: 'PENDING' | 'COMPLETED' | 'REJECTED'
          reason: string | null
          requested_at: string
          processed_by: string | null
          processed_at: string | null
          response_note: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      resource_types: {
        Row: Stamp & { id: string; company_id: string; name: string; description: string | null; is_active: boolean }
        Insert: { company_id: string; name: string; description?: string | null }
        Update: { name?: string; description?: string | null; is_active?: boolean }
        Relationships: []
      }
      branch_resources: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          resource_type_id: string
          total_quantity: number
          status: 'ACTIVE' | 'MAINTENANCE' | 'DISABLED'
        }
        Insert: {
          company_id: string
          branch_id: string
          resource_type_id: string
          total_quantity?: number
          status?: 'ACTIVE' | 'MAINTENANCE' | 'DISABLED'
        }
        Update: { total_quantity?: number; status?: 'ACTIVE' | 'MAINTENANCE' | 'DISABLED' }
        Relationships: []
      }
      service_resources: {
        Row: Stamp & { id: string; company_id: string; service_id: string; resource_type_id: string; quantity: number }
        Insert: never
        Update: never
        Relationships: []
      }
      branch_payment_accounts: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          promptpay_id: string
          account_name: string
          bank_name: string | null
          slipok_branch_id: string | null
          is_active: boolean
        }
        Insert: {
          company_id: string
          branch_id: string
          promptpay_id: string
          account_name: string
          bank_name?: string | null
          slipok_branch_id?: string | null
          is_active?: boolean
        }
        Update: {
          promptpay_id?: string
          account_name?: string
          bank_name?: string | null
          slipok_branch_id?: string | null
          is_active?: boolean
        }
        Relationships: []
      }
      resource_allocations: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          resource_type_id: string
          booking_item_id: string | null
          service_order_item_id: string | null
          quantity: number
          starts_at: string
          ends_at: string
          status: 'HELD' | 'RESERVED' | 'IN_USE' | 'RELEASED'
          expires_at: string | null
          released_at: string | null
          release_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      pos_sessions: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          status: 'OPEN' | 'CLOSED'
          business_date: string
          opened_at: string
          opened_by: string
          opening_cash: number
          opening_note: string | null
          closed_at: string | null
          closed_by: string | null
          review_status: 'PENDING' | 'APPROVED' | 'REJECTED' | null
          reviewed_by: string | null
          reviewed_at: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      service_orders: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          customer_id: string | null
          booking_id: string | null
          channel: 'ONLINE' | 'WALK_IN' | 'STAFF'
          business_date: string
          status: 'OPEN' | 'COMPLETED' | 'CANCELLED'
          note: string | null
          completed_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          cancel_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      service_order_items: {
        // therapist_fee ไม่ grant ให้ Client
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          service_order_id: string
          booking_item_id: string | null
          branch_service_option_id: string
          service_id: string
          service_name: string
          service_name_en: string | null
          duration_minutes: number
          unit_price: number
          quantity: number
          discount_amount: number
          line_total: number
          status: 'ACTIVE' | 'CANCELLED'
          cancelled_at: string | null
          cancelled_by: string | null
          cancel_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      queue_items: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          service_order_item_id: string
          queue_date: string
          queue_number: number
          follows_queue_id: string | null
          status: 'WAITING' | 'CALLED' | 'ACCEPTED' | 'IN_SERVICE' | 'COMPLETED' | 'CANCELLED'
          planned_starts_at: string
          planned_ends_at: string
          called_at: string | null
          called_by: string | null
          accepted_at: string | null
          accepted_by: string | null
          started_at: string | null
          started_by: string | null
          completed_at: string | null
          completed_by: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          cancel_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      service_assignments: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          queue_item_id: string
          employee_id: string
          status: 'ASSIGNED' | 'ACCEPTED' | 'IN_SERVICE' | 'COMPLETED' | 'CANCELLED'
          off_shift_confirmed: boolean
          handover_reason: string | null
          assigned_at: string
          assigned_by: string | null
          accepted_at: string | null
          accepted_by: string | null
          started_at: string | null
          completed_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          cancel_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      invoices: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          service_order_id: string
          customer_id: string | null
          business_date: string
          invoice_number: string | null
          receipt_number: string | null
          status: 'DRAFT' | 'ISSUED' | 'PARTIALLY_PAID' | 'PAID' | 'VOID'
          subtotal: number
          discount_total: number
          total: number
          paid_amount: number
          refunded_amount: number
          issued_at: string | null
          issued_by: string | null
          paid_at: string | null
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      invoice_items: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          invoice_id: string
          service_order_item_id: string
          description: string
          duration_minutes: number
          unit_price: number
          discount_amount: number
          discount_reason: string | null
          line_total: number
        }
        Insert: never
        Update: never
        Relationships: []
      }
      payments: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          invoice_id: string
          pos_session_id: string | null
          method: 'CASH' | 'BANK_TRANSFER' | 'QR' | 'DEPOSIT'
          amount: number
          status: 'SUCCESS' | 'VOID'
          verification: 'AUTO' | 'MANUAL' | null
          slip_check_id: string | null
          slip_trans_ref: string | null
          manual_reason: string | null
          booking_deposit_id: string | null
          received_by: string | null
          received_at: string
          voided_at: string | null
          voided_by: string | null
          void_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      tips: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          invoice_id: string | null
          payment_id: string | null
          employee_id: string
          pos_session_id: string
          method: 'CASH' | 'BANK_TRANSFER' | 'QR'
          amount: number
          status: 'RECORDED' | 'PAID_OUT' | 'VOID'
          paid_out_at: string | null
          paid_out_by: string | null
          payout_movement_id: string | null
          voided_at: string | null
          void_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      expenses: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string | null
          expense_scope: 'BRANCH' | 'HQ'
          amount: number
          note: string
          photo_path: string
          occurred_on: string
          payment_source: 'CASH_DRAWER' | 'OTHER'
          pos_session_id: string | null
          is_large: boolean
          status: 'RECORDED' | 'VOID'
          recorded_by: string | null
          void_requested_at: string | null
          void_requested_by: string | null
          void_request_reason: string | null
          voided_at: string | null
          voided_by: string | null
          void_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      pos_cash_movements: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          pos_session_id: string
          movement_type: 'CASH_IN' | 'CASH_OUT'
          category: 'ADJUSTMENT' | 'EXPENSE' | 'EXPENSE_REVERSAL' | 'TIP_PAYOUT'
          amount: number
          reason: string
          expense_id: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      employee_guarantee_rates: {
        Row: Stamp & {
          id: string
          company_id: string
          employee_id: string
          daily_amount: number
          effective_from: string
          effective_to: string | null
          status: 'ACTIVE' | 'CANCELLED'
          reason: string
        }
        Insert: never
        Update: never
        Relationships: []
      }
      staff_attendances: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          employee_id: string
          business_date: string
          clock_in_at: string
          clock_out_at: string | null
          clock_in_by: string | null
          clock_out_by: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      commissions: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          employee_id: string
          business_date: string
          kind: 'SERVICE' | 'GUARANTEE'
          service_assignment_id: string | null
          base_amount: number
          share_ratio: number | null
          amount: number
          status: 'ACCRUED' | 'PAID' | 'VOID'
          payout_id: string | null
          void_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      commission_adjustments: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string | null
          employee_id: string
          business_date: string
          amount: number
          source: 'MANUAL' | 'VOID_REVERSAL' | 'GUARANTEE_RECALC'
          commission_id: string | null
          reason: string
          status: 'OPEN' | 'PAID'
          payout_id: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      branch_daily_closings: {
        Row: Stamp & {
          id: string
          company_id: string
          branch_id: string
          business_date: string
          status: 'SUBMITTED' | 'APPROVED' | 'REJECTED'
          figures: Json
          submit_note: string | null
          submitted_by: string | null
          submitted_at: string
          reviewed_by: string | null
          reviewed_at: string | null
          review_note: string | null
          adjustment_amount: number
          adjustment_note: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      financial_periods: {
        Row: Stamp & {
          id: string
          company_id: string
          period_start: string
          status: 'LOCKED' | 'OPEN'
          locked_at: string | null
          locked_by: string | null
          reopened_at: string | null
          reopened_by: string | null
          reopen_reason: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
    }
    Views: {
      v_public_branch_services: {
        Row: {
          option_id: string
          branch_service_id: string
          company_id: string
          branch_id: string
          service_id: string
          name: string
          name_en: string | null
          description: string | null
          image_path: string | null
          category_id: string
          category_name: string
          duration_minutes: number
          price: number
          sort_order: number
          category_sort_order: number
        }
        Relationships: []
      }
    }
    Functions: {
      my_access: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      pair_branch_device: {
        Args: { p_branch_id: string; p_name: string }
        Returns: Json
      }
      revoke_branch_device: {
        Args: { p_device_id: string; p_reason: string }
        Returns: undefined
      }
      set_staff_pin: {
        Args: { p_company_id: string; p_user_id: string; p_pin: string }
        Returns: undefined
      }
      change_my_pin: {
        Args: { p_company_id: string; p_current_pin: string; p_new_pin: string }
        Returns: undefined
      }
      assert_can_manage_staff: {
        Args: { p_company_id: string }
        Returns: undefined
      }
      transfer_employee: {
        Args: { p_employee_id: string; p_to_branch_id: string; p_effective_from: string; p_reason: string }
        Returns: string
      }
      cancel_employee_transfer: {
        Args: { p_transfer_id: string; p_reason: string }
        Returns: undefined
      }
      copy_schedule_week: {
        Args: { p_branch_id: string; p_source_monday: string; p_target_monday: string }
        Returns: Json
      }
      save_branch_service_pricing: {
        Args: {
          p_branch_ids: string[]
          p_service_id: string
          p_options: Json
          p_effective_from: string | null
          p_reason: string | null
        }
        Returns: Json
      }
      owner_service_pricing: {
        Args: { p_branch_id: string }
        Returns: Json
      }
      cancel_scheduled_price: {
        Args: { p_price_history_id: string; p_reason: string }
        Returns: undefined
      }
      get_public_company: {
        Args: { p_code: string }
        Returns: Json
      }
      get_current_policies: {
        Args: { p_company_code: string }
        Returns: Json
      }
      register_customer: {
        Args: {
          p_company_code: string
          p_first_name: string
          p_last_name: string
          p_phone: string
          p_privacy_version_id: string
          p_marketing_consent: boolean
        }
        Returns: string
      }
      my_customer: {
        Args: { p_company_code: string }
        Returns: Json
      }
      update_my_customer: {
        Args: { p_company_code: string; p_first_name: string; p_last_name: string; p_phone: string }
        Returns: undefined
      }
      set_my_marketing_consent: {
        Args: { p_company_code: string; p_granted: boolean }
        Returns: undefined
      }
      export_my_data: {
        Args: { p_company_code: string }
        Returns: Json
      }
      request_my_data_deletion: {
        Args: { p_company_code: string; p_reason: string }
        Returns: string
      }
      search_customers_by_phone: {
        Args: { p_company_id: string; p_phone: string }
        Returns: {
          customer_id: string
          display_name: string
          phone_masked: string
          is_member: boolean
          created_at: string
        }[]
      }
      get_customer: {
        Args: { p_customer_id: string }
        Returns: Json
      }
      create_customer: {
        Args: {
          p_company_id: string
          p_first_name: string
          p_last_name: string
          p_phone: string
          p_email: string | null
          p_staff_note: string | null
          p_privacy_acknowledged: boolean
        }
        Returns: string
      }
      update_customer: {
        Args: {
          p_customer_id: string
          p_first_name: string
          p_last_name: string
          p_phone: string
          p_email: string | null
          p_staff_note: string | null
        }
        Returns: undefined
      }
      set_service_resources: {
        Args: { p_service_id: string; p_items: Json }
        Returns: undefined
      }
      get_available_slots: {
        Args: { p_branch_id: string; p_date: string; p_option_ids: string[] }
        Returns: Json
      }
      create_member_booking: {
        Args: {
          p_company_code: string
          p_branch_id: string
          p_starts_at: string
          p_option_ids: string[]
          p_note: string | null
          p_idempotency_key: string
        }
        Returns: Json
      }
      my_bookings: { Args: { p_company_code: string }; Returns: Json }
      my_booking: { Args: { p_company_code: string; p_booking_id: string }; Returns: Json }
      cancel_my_booking: { Args: { p_company_code: string; p_booking_id: string; p_reason: string | null }; Returns: Json }
      staff_create_booking: {
        Args: {
          p_branch_id: string
          p_customer_id: string
          p_starts_at: string
          p_option_ids: string[]
          p_note: string | null
          p_collect_deposit: boolean
          p_idempotency_key: string
        }
        Returns: Json
      }
      staff_bookings: { Args: { p_branch_id: string; p_date: string }; Returns: Json }
      review_deposit: { Args: { p_deposit_id: string; p_approve: boolean; p_note: string | null }; Returns: undefined }
      staff_cancel_booking: { Args: { p_booking_id: string; p_reason: string; p_force_refund?: boolean }; Returns: undefined }
      mark_no_show: { Args: { p_booking_id: string }; Returns: undefined }
      record_deposit_refund: { Args: { p_booking_id: string; p_reference: string }; Returns: undefined }
      set_booking_staff_note: { Args: { p_booking_id: string; p_note: string | null }; Returns: undefined }
      pos_open_session: {
        Args: { p_branch_id: string; p_opening_cash: number; p_note: string | null }
        Returns: string
      }
      pos_available_starts: { Args: { p_branch_id: string; p_option_ids: string[] }; Returns: Json }
      pos_create_walkin: {
        Args: {
          p_branch_id: string
          p_customer_id: string | null
          p_starts_at: string
          p_option_ids: string[]
          p_note: string | null
          p_idempotency_key: string
        }
        Returns: Json
      }
      pos_add_order_items: {
        Args: { p_order_id: string; p_starts_at: string; p_option_ids: string[]; p_idempotency_key: string }
        Returns: Json
      }
      pos_check_in_booking: { Args: { p_booking_id: string }; Returns: Json }
      queue_call: {
        Args: { p_queue_id: string; p_employee_id: string; p_confirm_off_shift?: boolean; p_reason?: string | null }
        Returns: Json
      }
      queue_accept: { Args: { p_queue_id: string }; Returns: Json }
      queue_start: { Args: { p_queue_id: string }; Returns: Json }
      queue_complete: { Args: { p_queue_id: string }; Returns: Json }
      queue_cancel: { Args: { p_queue_id: string; p_reason: string }; Returns: Json }
      pos_board: { Args: { p_branch_id: string; p_date?: string | null }; Returns: Json }
      queue_extend: { Args: { p_queue_id: string; p_option_id: string; p_idempotency_key: string }; Returns: Json }
      queue_handover: {
        Args: { p_queue_id: string; p_employee_id: string; p_reason: string; p_confirm_off_shift?: boolean }
        Returns: Json
      }
      queue_undo_start: { Args: { p_queue_id: string; p_reason: string }; Returns: Json }
      queue_undo_complete: { Args: { p_queue_id: string; p_reason: string }; Returns: Json }
      my_service_history: { Args: { p_company_code: string }; Returns: Json }
      my_work_history: { Args: { p_from: string; p_to: string }; Returns: Json }
      therapist_work_summary: {
        Args: { p_company_id: string; p_branch_id: string | null; p_from: string; p_to: string }
        Returns: Json
      }
      staff_dashboard: { Args: { p_branch_id: string }; Returns: Json }
      pos_create_invoice: { Args: { p_order_id: string }; Returns: Json }
      pos_set_invoice_discount: { Args: { p_invoice_item_id: string; p_amount: number; p_reason: string | null }; Returns: Json }
      pos_issue_invoice: { Args: { p_invoice_id: string }; Returns: Json }
      pos_record_payment: {
        Args: {
          p_invoice_id: string
          p_method: string
          p_amount: number
          p_slip_check_id: string | null
          p_manual_reason: string | null
          p_tip_amount: number
          p_tip_employee_id: string | null
          p_idempotency_key: string
        }
        Returns: Json
      }
      pos_void_invoice: { Args: { p_invoice_id: string; p_reason: string; p_idempotency_key: string }; Returns: Json }
      pos_refund_payment: {
        Args: { p_payment_id: string; p_amount: number; p_method: string; p_reference: string | null; p_reason: string; p_idempotency_key: string }
        Returns: Json
      }
      pos_cash_adjustment: { Args: { p_branch_id: string; p_type: string; p_amount: number; p_reason: string }; Returns: string }
      pos_pay_out_tips: { Args: { p_branch_id: string; p_employee_id: string }; Returns: Json }
      pos_close_session: { Args: { p_session_id: string; p_actual_cash: number; p_note: string | null }; Returns: Json }
      pos_review_session: { Args: { p_session_id: string; p_approve: boolean; p_note: string | null }; Returns: undefined }
      pos_sessions_list: { Args: { p_branch_id: string; p_from: string; p_to: string }; Returns: Json }
      pos_record_expense: {
        Args: {
          p_company_id: string
          p_branch_id: string | null
          p_amount: number
          p_note: string
          p_photo_path: string
          p_from_drawer: boolean
          p_occurred_on: string | null
        }
        Returns: string
      }
      pos_void_expense: { Args: { p_expense_id: string; p_reason: string }; Returns: string }
      pos_reject_expense_void: { Args: { p_expense_id: string; p_note: string | null }; Returns: undefined }
      expenses_list: { Args: { p_company_id: string; p_branch_id: string | null; p_from: string; p_to: string }; Returns: Json }
      pos_invoice: { Args: { p_invoice_id: string }; Returns: Json }
      pos_finance_board: { Args: { p_branch_id: string }; Returns: Json }
      staff_dashboard_finance: { Args: { p_branch_id: string }; Returns: Json }
      attendance_clock: { Args: { p_branch_id: string; p_action: string }; Returns: Json }
      branch_attendance_today: { Args: { p_branch_id: string }; Returns: Json }
      set_employee_guarantee: {
        Args: { p_employee_id: string; p_daily_amount: number; p_effective_from: string; p_reason: string }
        Returns: undefined
      }
      set_guarantee_override: {
        Args: { p_employee_id: string; p_branch_id: string; p_date: string; p_grant: boolean; p_reason: string }
        Returns: undefined
      }
      attendance_report: { Args: { p_company_id: string; p_branch_id: string | null; p_from: string; p_to: string }; Returns: Json }
      create_commission_payout: { Args: { p_company_id: string; p_period_to: string }; Returns: Json }
      confirm_commission_payout: {
        Args: { p_payout_id: string; p_method: string; p_reference: string | null; p_note: string | null }
        Returns: Json
      }
      cancel_commission_payout: { Args: { p_payout_id: string }; Returns: undefined }
      add_commission_adjustment: {
        Args: { p_employee_id: string; p_branch_id: string | null; p_amount: number; p_reason: string }
        Returns: string
      }
      commission_summary: { Args: { p_company_id: string; p_branch_id: string | null; p_from: string; p_to: string }; Returns: Json }
      daily_closing_preview: { Args: { p_branch_id: string; p_date: string }; Returns: Json }
      submit_daily_closing: { Args: { p_branch_id: string; p_date: string; p_note: string | null }; Returns: string }
      review_daily_closing: {
        Args: { p_closing_id: string; p_approve: boolean; p_note: string | null; p_adjustment_amount: number; p_adjustment_note: string | null }
        Returns: undefined
      }
      daily_closings_list: { Args: { p_company_id: string; p_branch_id: string | null; p_from: string; p_to: string }; Returns: Json }
      lock_financial_period: { Args: { p_company_id: string; p_month: string }; Returns: undefined }
      reopen_financial_period: { Args: { p_company_id: string; p_month: string; p_reason: string }; Returns: undefined }
      financial_periods_list: { Args: { p_company_id: string }; Returns: Json }
      finance_report: {
        Args: { p_company_id: string; p_branch_id: string | null; p_from: string; p_to: string; p_group: string }
        Returns: Json
      }
      owner_dashboard: { Args: { p_company_id: string }; Returns: Json }
      abnormal_expenses: { Args: { p_company_id: string; p_from: string; p_to: string }; Returns: Json }
      my_earnings: { Args: { p_from: string; p_to: string }; Returns: Json }
      merge_customers: {
        Args: { p_source_id: string; p_target_id: string; p_reason: string }
        Returns: undefined
      }
    }
    Enums: { [_ in never]: never }
    CompositeTypes: { [_ in never]: never }
  }
}

export type Tables<T extends keyof Database['public']['Tables']> = Database['public']['Tables'][T]['Row']
