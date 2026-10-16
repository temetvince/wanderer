import { UserPermission } from '@/hooks/Mapper/types/permissions.ts';

export type StringBoolean = 'true' | 'false';

export type MapOptions = {
  allowed_copy_for: UserPermission;
  allowed_paste_for: UserPermission;
  layout: string;
  restrict_offline_showing: StringBoolean;
  show_linked_signature_id: StringBoolean;
  show_linked_signature_id_temp_name: StringBoolean;
  show_temp_system_name: StringBoolean;
  store_custom_labels: StringBoolean;
  // Fork: server-side auto-label formats per target; 'disabled' turns a target off.
  auto_label_jumped_label: string;
  auto_label_jumped_tag: string;
  auto_label_jumped_temp_name: string;
  // Fork: only custom-named systems keep their status when removed from the map.
  clear_status_on_removal: StringBoolean;
};
