const instanceIndex = process.env.CF_INSTANCE_INDEX || '0';
const appName = process.env.VCAP_APPLICATION
  ? JSON.parse(process.env.VCAP_APPLICATION).application_name
  : 'worker-app';

let counter = 0;

function tick() {
  counter++;
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${appName} instance ${instanceIndex}: tick #${counter}`);
}

// Log every 5 seconds
const interval = setInterval(tick, 5000);

// Initial log
console.log(`Worker started: ${appName} instance ${instanceIndex}`);
tick();

// Graceful shutdown
process.once('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  clearInterval(interval);
  process.exit(0);
});
