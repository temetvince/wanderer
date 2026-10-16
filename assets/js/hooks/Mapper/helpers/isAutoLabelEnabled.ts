import { MapOptions } from '@/hooks/Mapper/types';

const AUTO_LABEL_FORMAT_KEYS = [
  'auto_label_jumped_label',
  'auto_label_jumped_tag',
  'auto_label_jumped_temp_name',
] as const;

/**
 * Fork: true when the map's server-side auto-labeling writes at least one
 * target (custom label, tag or temporary name). Mirrors the server's notion of
 * the feature being on: any format option other than 'disabled'.
 */
export const isAutoLabelEnabled = (options: Partial<MapOptions> | undefined): boolean =>
  AUTO_LABEL_FORMAT_KEYS.some(key => {
    const value = options?.[key];
    return typeof value === 'string' && value !== '' && value !== 'disabled';
  });
