import { NativeEventEmitter, NativeModules, Platform } from 'react-native';
import type { OpenIDBLEShare } from './types/bleshare';
import { tuvaliVersion } from './tuvaliVersion';

const LINKING_ERROR =
  `The package 'react-native-openid4vp-ble' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

const Openid4vpBle: OpenIDBLEShare = NativeModules.Openid4vpBle
  ? NativeModules.Openid4vpBle
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

Openid4vpBle.setTuvaliVersion(tuvaliVersion);

if (Platform.OS === 'android') {
  const eventEmitter = new NativeEventEmitter();
  Openid4vpBle.handleNearbyEvents = (callback) =>
    eventEmitter.addListener('EVENT_NEARBY', callback);
  Openid4vpBle.handleLogEvents = (callback) =>
    eventEmitter.addListener('EVENT_LOG', callback);
}

if (Platform.OS === 'ios') {
  console.log(`IOS PLATFORM`);
  const eventEmitter = new NativeEventEmitter(NativeModules.Openid4vpBle);
  Openid4vpBle.handleNearbyEvents = (callback) =>
    eventEmitter.addListener('EVENT_NEARBY', callback);
  Openid4vpBle.handleLogEvents = (callback) =>
    eventEmitter.addListener('EVENT_LOG', callback);
}

export default {
  Openid4vpBle,
};
