import { MIN_PORT, EXCLUDED_PROCESS_NAMES } from './constants.js';

export function isFiltered(service) {
  if (service.port < MIN_PORT) return true;
  if (EXCLUDED_PROCESS_NAMES.includes(service.command)) return true;
  return false;
}

export function filterServices(services) {
  return services.filter((service) => !isFiltered(service));
}
